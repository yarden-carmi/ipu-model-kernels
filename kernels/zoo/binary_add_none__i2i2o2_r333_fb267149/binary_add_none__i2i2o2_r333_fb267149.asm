{% set padded = (in0_d1 * in0_d2) % 128 != 0 %}
{% set shifted = (out0_d0 * out0_d1) % 128 != 0 %}
{% set partial = (out0_d1 * out0_d2) % 128 != 0 %}
{% macro store(mask) %}
    LD.MULT R0 LR1 {{ cr.in1 }} ; SET LR2 CR0 ; SET LR3 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; DEC LR2 1 ;;
{% endmacro %}

// LR4 is a, LR5 is a + A*b. LR6/LR7 point at the source row/lane.
// LR2 counts destination lanes, spanning logical rows within a packed group.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR11 127 ; INC LR12 128 ;;
batch:
    SET LR5 LR4 ; SET LR8 {{ cr.out0_d1 }} ; SET LR2 CR0 ;;
    DEC LR2 1 ;;
logical_row:
    SET LR6 CR0 ; SET LR7 LR5 ; SET LR9 {{ cr.out0_d2 }} ;;
{% if padded %}
    SET LR10 LR5 ;;
plane_wrap:
    BLT.S LR10 LR13 normalize ;;
    SUB LR10 LR10 LR13 ; ADD LR7 LR7 LR15 ; B plane_wrap ;;
{% endif %}
normalize:
    BLT.S LR7 LR12 gather ;;
    DEC LR7 128 ; INC LR6 1 ; B normalize ;;
gather:
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR9 1 ;;
    MULT.EE LR7 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.single }}.L ; INC LR2 1 ;;
    BLT.S LR2 LR11 advance ;;
    {{ store('CR15.L') }}
advance:
    BEQ LR9 CR0 next_logical ;;
    ADD LR6 LR6 {{ cr.rowstep }} ; ADD LR7 LR7 {{ cr.lanestep }} ;;
{% if padded %}
    ADD LR10 LR10 LR14 ; B plane_wrap ;;
{% elif shifted %}
    B normalize ;;
{% else %}
    B gather ;;
{% endif %}
next_logical:
    DEC LR8 1 ; ADD LR5 LR5 {{ cr.out0_d0 }} ;;
    BNE LR8 CR0 logical_row ;;
{% if partial %}
    {{ store(cr.tail ~ '.L') }}
{% endif %}
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.out0_d0 }} batch ;;
    HALT ;;
