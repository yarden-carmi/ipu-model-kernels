{% macro flush(mask) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; SET LR2 CR0 ;;
{% endmacro %}

{% set stride = out0_d0 * out0_d1 % in0_d2 %}
{% set group = 128 if in0_d2 % 128 == 0 and stride % 128 == 0 else
                64 if in0_d2 % 64 == 0 and stride % 64 == 0 else
                32 if in0_d2 % 32 == 0 and stride % 32 == 0 else
                16 if in0_d2 % 16 == 0 and stride % 16 == 0 else
                 8 if in0_d2 % 8 == 0 and stride % 8 == 0 else 1 %}
{% set phases = in0_d2 // group %}
{% set periodic = phases <= 32 and out0_d0 * out0_d1 <= 32767 %}
{% macro advance(reg, delta) %}
{% if delta > 0 %} INC {{ reg }} {{ delta }} ;
{% elif delta < 0 %} DEC {{ reg }} {{ -delta }} ;
{% endif %}
{% endmacro %}

// LR4:LR5 is the padded row and unpadded lane of a + A*b.
// LR6:LR7 advances by A*B for each logical column.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR14 CR0 ; SET LR13 CR0 ;;
    INC LR13 128 ;;
    ADD LR8 LR13 LR13 ;;
{% if periodic %}
    DEC LR3 1 ;;
{% endif %}
batch:
    SET LR4 CR0 ; SET LR5 LR14 ; SET LR15 {{ cr.dims }}.H ;;
origin:
    BLT.S LR5 {{ cr.span }}.L row ;;
    SUB LR5 LR5 {{ cr.span }}.L ; ADD LR4 LR4 {{ cr.span }}.H ; B origin ;;
row:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR12 {{ cr.out0_d2 }} ;;
chunk:
{% if periodic %}
    // Compute input-chunk length once, then cut it at the output boundary.
    SET LR11 LR13 ; SET LR9 LR12 ; BLT.S LR12 LR13 take_chunk ;;
    SET LR9 LR13 ;;
take_chunk:
    LD.MULT R1 LR3 {{ cr.in1 }} ; INC LR3 1 ; SUB LR12 LR12 LR9 ; DEC LR11 1 ;;
segment:
    SUB LR10 LR13 LR2 ; ADD LR8 LR11 LR9 ;;
    BLT.S LR9 LR10 sized ;;
    SET LR9 LR10 ;;
sized:
    ADD LR10 LR2 LR9 ; DEC LR2 1 ; SET LR9 CR0 ;;
    DEC LR10 2 ; INC LR9 {{ group }} ;;
    // The lane remainder within a group is invariant. Dispatch once, then
    // use fixed physical row/lane deltas and load the next row with the add.
{% for p in range(phases) %}
    {% if not loop.last %}
    BLT.S LR7 LR9 enter_{{ p }} ; INC LR9 {{ group }} ;;
    {% else %}
    B enter_{{ p }} ;;
    {% endif %}
{% endfor %}
{% for p in range(phases) %}
    {% set col = p * group %}
    {% set next = (col + stride) % in0_d2 %}
    {% set dr = ((out0_d0 * out0_d1 + col) // in0_d2) * ((in0_d2 + 127) // 128) + next // 128 - col // 128 %}
enter_{{ p }}:
    {% if col >= 128 %}
    INC LR6 1 ; DEC LR7 128 ;;
    {% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ;;
phase_{{ p }}:
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.scalar }}.L ; {{ advance('LR6', dr) }} {{ advance('LR7', next % 128 - col % 128) }} INC LR2 1 ; BEQ LR2 LR10 {{ 'exit_high' if next >= 128 else 'exit_segment' }} ;;
    MULT.EE LR11 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; AGG.SUM LR2 {{ cr.scalar }}.L ; LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR11 1 ; SET LR9 LR7 ; B phase_{{ next // group }} ;;
{% endfor %}
{% if in0_d2 > 128 %}
exit_high:
    DEC LR6 1 ; INC LR7 128 ;;
{% endif %}
exit_segment:
    MULT.EE LR11 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; AGG.SUM LR2 {{ cr.scalar }}.L ; INC LR11 1 ;;
    INC LR2 1 ;;
    BNE LR2 LR13 segment_done ;;
    {{ flush('CR15.L') }}
segment_done:
    SUB LR9 LR8 LR11 ; BNE LR11 LR8 segment ;;
    BNE LR12 CR0 chunk ;;
{% else %}
    LD.MULT R1 LR3 {{ cr.in1 }} ; SET LR11 LR13 ;;
    INC LR3 1 ;;
gather:
    BLT.S LR7 {{ cr.span }}.L locate ;;
    SUB LR7 LR7 {{ cr.span }}.L ; ADD LR6 LR6 {{ cr.span }}.H ;;
locate:
{% if in0_d2 > 128 %}
    BLT.S LR7 LR13 load ; SET LR9 LR7 ; SET LR10 LR6 ;;
    INC LR10 1 ; DEC LR9 128 ;;
load:
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% else %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ;;
{% endif %}
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.scalar }}.L ;;
    MULT.EE LR11 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; AGG.SUM LR2 {{ cr.scalar }}.L ;
    ADD LR6 LR6 {{ cr.step_row }} ; ADD LR7 LR7 {{ cr.step_lane }} ; DEC LR12 1 ;;
    INC LR2 1 ; INC LR11 1 ;;
    BNE LR2 LR13 advance ;;
    {{ flush('CR15.L') }}
advance:
    BEQ LR12 CR0 end_row ;;
    // R1 indices are 128..255; the next source chunk starts at 256.
    BLT.S LR11 LR8 gather ;;
    B chunk ;;
{% endif %}
end_row:
{% if out0_d2 <= 144 %}
    BEQ LR2 CR0 next_row ;;
    {{ flush(cr.tail ~ '.L') }}
next_row:
{% endif %}
    DEC LR15 1 ; ADD LR5 LR5 {{ cr.dims }}.L ;;
    BNE LR15 CR0 origin ;;
{% if out0_d2 > 144 %}
    BEQ LR2 CR0 next_batch ;;
    {{ flush(cr.tail ~ '.L') }}
next_batch:
{% endif %}
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.dims }}.L batch ;;
    HALT ;;
