// Visit planes in (d2,d1,d0) order. This is the flat storage order
// for the strided view and the physical row order for in1 and out0.
{% set plane = out0_d0 * out0_d1 %}
{% set valid = (plane - 1) % 128 + 1 %}
{% macro load_first(ds) %}
    MULT.VE LR4 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;
{% endmacro %}
{% macro store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
{% endmacro %}

{% if plane % 128 == 0 %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
row:
    {{ load_first('CR15.L') }} ;;
    {{ store('CR15.L') }} BLT.S LR1 {{ cr.last_row }} next ;;
    HALT ;;
next:
    INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; B row ;;
{% else %}
// LR2:LR4 is the flat input cursor (row:lane). Full output rows
// leave the lane unchanged; tails consume only their active lanes.
    INC LR6 128 ;;
plane_start:
    SET LR3 CR0 ;;
{% if plane > 128 %}
full_row:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    INC LR2 1 ; BEQ LR4 CR0 full_ready ;;
    LD.MULT R1 LR2 {{ cr.in0 }} ;;
full_ready:
    {{ load_first('CR15.L') }} ;;
    {{ store('CR15.L') }} INC LR1 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.full }} full_row ;;
{% endif %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR5 LR4 ;;
    INC LR5 {{ valid }} ;;
    BLT.S LR6 LR5 tail_cross ;;
    B tail_ready ;;
tail_cross:
    ADD LR7 LR2 CR1 ;;
    LD.MULT R1 LR7 {{ cr.in0 }} ;;
tail_ready:
    {{ load_first(cr.tail ~ '.L') }} ;;
    {{ store(cr.tail ~ '.L') }} BEQ LR1 {{ cr.last_row }} finish ;;
    INC LR1 1 ; SET LR4 LR5 ; BLT.S LR5 LR6 plane_start ;;
    DEC LR4 128 ; INC LR2 1 ; B plane_start ;;
finish:
    HALT ;;
{% endif %}
