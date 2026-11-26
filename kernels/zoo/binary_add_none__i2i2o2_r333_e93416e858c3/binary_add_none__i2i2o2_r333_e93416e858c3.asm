{% set stride = out0_d0 * out0_d1 % in0_d2 %}
{% set group = 128 if in0_d2 % 128 == 0 and stride % 128 == 0 else
                64 if in0_d2 % 64 == 0 and stride % 64 == 0 else
                32 if in0_d2 % 32 == 0 and stride % 32 == 0 else
                16 if in0_d2 % 16 == 0 and stride % 16 == 0 else
                 8 if in0_d2 % 8 == 0 and stride % 8 == 0 else 1 %}
{% set phases = in0_d2 // group %}
{% set periodic = in0_d2 <= 256 and phases <= 32 and out0_d0 * out0_d1 <= 32767 and out0_d2 % 128 != 1 %}
{% macro advance(reg, delta) %}
{% if delta > 0 %} INC {{ reg }} {{ delta }} ;
{% elif delta < 0 %} DEC {{ reg }} {{ -delta }} ;
{% endif %}
{% endmacro %}
{% macro gather_scalar() %}
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.scalar }}.L ;
{% endmacro %}
{% macro store(mask) %}
    LD.MULT R0 LR1 {{ cr.in1 }} ; SET LR2 CR0 ; SET LR3 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR14 CR0 ;;
    SET LR13 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR13 128 ;;
batch:
    SET LR4 CR0 ; SET LR5 LR14 ; SET LR15 {{ cr.dims }}.H ;;
// The row starts at flat storage offset a + A*b; c advances by A*B.
origin:
    BLT.S LR5 {{ cr.span }}.L row ;;
    SUB LR5 LR5 {{ cr.span }}.L ; ADD LR4 LR4 {{ cr.span }}.H ; B origin ;;
row:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR12 {{ cr.out0_d2 }} ;;
chunk:
    BGE.S LR13 LR12 tail_chunk ; SET LR11 LR12 ;;
    SET LR11 LR13 ; DEC LR12 128 ; B start_gather ;;
tail_chunk:
    SET LR12 CR0 ;;
start_gather:
// AGG sees the incremented destination; the branch sees the old cursor.
    DEC LR2 1 ; DEC LR11 {{ 3 if periodic else 2 }} ;;
{% if periodic %}
// The stride preserves the remainder within each group. Dispatch once per
// output chunk, then walk a fixed cycle of physical row/lane deltas.
    SET LR10 CR0 ;;
    INC LR10 {{ group }} ;;
{% for p in range(phases) %}
    {% set target = 'prime_' ~ p %}
    {% if not loop.last %}
    BLT.S LR7 LR10 {{ target }} ; INC LR10 {{ group }} ;;
    {% else %}
    B {{ target }} ;;
    {% endif %}
{% endfor %}
{% for p in range(phases) %}
    {% set col = p * group %}
    {% set next_col = (col + stride) % in0_d2 %}
    {% set dr = ((out0_d0 * out0_d1 + col) // in0_d2) * ((in0_d2 + 127) // 128) + next_col // 128 - col // 128 %}
    {% set prev_col = (col - stride) % in0_d2 %}
    {% set next2_col = (next_col + stride) % in0_d2 %}
    {% set dr2 = ((out0_d0 * out0_d1 + next_col) // in0_d2) * ((in0_d2 + 127) // 128) + next2_col // 128 - next_col // 128 %}
prime_{{ p }}:
    {% if col >= 128 %} INC LR6 1 ; DEC LR7 128 ;; {% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ;;
    {{ advance('LR9', prev_col % 128 - col % 128) }} B phase_{{ p }} ;;
phase_{{ p }}:
    // Consume the primed row while loading its successor using the updated LR6.
    {{ gather_scalar() }} LD.MULT R0 LR6 {{ cr.in0 }} ;
    {{ advance('LR6', dr) }} {{ advance('LR9', col % 128 - prev_col % 128) }} INC LR2 1 ; BNE LR2 LR11 phase_{{ next_col // group }} ;;
    // Drain without loading past the chunk, then restore the logical cursor.
    {{ gather_scalar() }} INC LR2 1 ; {{ advance('LR9', next_col % 128 - col % 128) }} {{ advance('LR6', dr2) }} ;;
    SET LR7 LR9 ;;
    {{ advance('LR7', next2_col - next_col % 128) }} {% if next2_col >= 128 %} DEC LR6 1 ; {% endif %} B gathered ;;
{% endfor %}
gathered:
{% else %}
gather:
    BLT.S LR7 {{ cr.span }}.L locate ;;
    SUB LR7 LR7 {{ cr.span }}.L ; ADD LR6 LR6 {{ cr.span }}.H ;;
locate:
{% if in0_d2 <= 128 %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ;;
{% elif in0_d2 <= 256 %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ; ADD LR10 LR6 CR1 ; BLT.S LR7 LR13 loaded ;;
    LD.MULT R0 LR10 {{ cr.in0 }} ; SUB LR9 LR7 LR13 ;;
loaded:
{% else %}
    SET LR10 LR6 ; SET LR9 LR7 ;;
physical_chunk:
    BLT.S LR9 LR13 load ;;
    INC LR10 1 ; DEC LR9 128 ; B physical_chunk ;;
load:
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% endif %}
    {{ gather_scalar() }}
    ADD LR6 LR6 {{ cr.step_row }} ; ADD LR7 LR7 {{ cr.step_lane }} ; INC LR2 1 ; BNE LR2 LR11 gather ;;
{% endif %}
    BEQ LR12 CR0 end_row ;;
    {{ store('CR15.L') }}
    B chunk ;;
end_row:
    {{ store(cr.tail ~ '.L') }}
    DEC LR15 1 ; ADD LR5 LR5 {{ cr.dims }}.L ;;
    BNE LR15 CR0 origin ;;
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.dims }}.L batch ;;
    HALT ;;
