{% set step = out0_d0 * out0_d1 % in0_d2 %}
{% set width = (in0_d0 * in0_d1 + 127) // 128 %}
{% set bstep = out0_d0 * out0_d1 // in0_d2 * in0_d0 %}
{% set full = cr.ds_pair ~ '.L' %}
{% macro inc(reg, n) %}
{% if 0 < n < 256 %}
    INC {{ reg }} {{ n }} ;;
{% elif n >= 256 %}
    SET LR13 CR0 ;;
{% for bit in range(22, -1, -1) if 2**bit <= n %}
{% if 2**(bit + 1) <= n %}
    ADD LR13 LR13 LR13 ;;
{% endif %}
{% if (n // 2**bit) % 2 %}
    INC LR13 1 ;;
{% endif %}
{% endfor %}
    ADD {{ reg }} {{ reg }} LR13 ;;
{% endif %}
{% endmacro %}
{% macro store(mask) %}
    LD.MULT R0 LR4 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; SET LR3 CR0 ;;
{% endmacro %}

// Decode the view's flat address into stored (a,b,c). LR6 is c,
// LR7 is b*in0_d0, LR8 is a, and LR9 is the first physical row of c.
// The destination row stays open across logical row boundaries.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ;;
batch:
    SET LR12 LR1 ; SET LR14 {{ cr.batch_size }} ;;
row:
    SET LR6 LR12 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; SET LR15 {{ cr.out0_d2 }} ;;
seed:
    BLT.S LR6 {{ cr.column_ds }}.L wrap_b ;;
    SUB LR6 LR6 {{ cr.column_ds }}.L ; INC LR7 {{ in0_d0 }} ;;
    B seed ;;
wrap_b:
    BLT.S LR7 {{ cr.plane }} gather ;;
    SUB LR7 LR7 {{ cr.plane }} ; INC LR8 1 ; B wrap_b ;;
gather:
    // At a new logical row only, seed LR9 from its column remainder.
    BNE LR15 {{ cr.out0_d2 }} locate ; SET LR10 LR6 ;;
seed_rows:
    BEQ LR10 CR0 locate ;;
    {{ inc('LR9', width) }}
    DEC LR10 1 ; B seed_rows ;;
locate:
    ADD LR11 LR7 LR8 ; SET LR10 LR9 ;;
{% if width > 1 %}
lane_row:
    BLT.S LR11 {{ cr.lanes }} load ;;
    DEC LR11 128 ; INC LR10 1 ; B lane_row ;;
{% endif %}
load:
    LD.MULT R0 LR10 {{ cr.in0 }} ; DEC LR14 1 ; DEC LR15 1 ;;
    MULT.EE LR11 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.column_ds }}.H ; BEQ LR14 CR0 tail ;;
    INC LR3 1 ;;
    BNE LR3 {{ cr.lanes }} next ;;
    {{ store(full) }}
next:
    BEQ LR15 CR0 next_row ;;
    {{ inc('LR6', step) }}
    {{ inc('LR9', step * width) }}
    {{ inc('LR7', bstep) }}
{% if step %}
    BLT.S LR6 {{ cr.column_ds }}.L wrap_b ;;
    SUB LR6 LR6 {{ cr.column_ds }}.L ; SUB LR9 LR9 {{ cr.src_rows }} ; INC LR7 {{ in0_d0 }} ;;
{% endif %}
    B wrap_b ;;
next_row:
    ADD LR12 LR12 {{ cr.out0_d0 }} ; B row ;;
tail:
    {{ store(cr.ds_pair ~ '.H') }}
    INC LR1 1 ;;
    BNE LR1 {{ cr.out0_d0 }} batch ;;
    HALT ;;
