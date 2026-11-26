{% macro add_store(ds) %}
    LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    SET LR2 LR14 ;;
    INC LR9 128 ;;
row:
    SET LR3 LR9 ;;
    BNE LR2 CR1 gather_start ;;
    SET LR3 LR15 ;;
gather_start:
    SET LR4 CR0 ;;
gather:
    LD.MULT R0 LR5 {{ cr.in0 }} ; INC LR6 1 ;;
    MULT.EE LR7 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR4 {{ cr.one }}.L ; ADD LR5 LR5 {{ cr.src_width }} ; BEQ LR6 {{ cr.in0_d2 }} next_column ;;
advance:
    INC LR4 1 ;;
    BLT.S LR4 LR3 gather ;;
    BEQ LR2 CR1 tail ;;
    {{ add_store('CR15.L') }}
    DEC LR2 1 ; INC LR1 1 ; B row ;;
tail:
    {{ add_store(cr.tail ~ '.L') }}
    SET LR2 LR14 ; INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;

# Carry the flat view index through the stored tensor's coordinates.
next_column:
    SET LR6 CR0 ; INC LR8 1 ;;
    BEQ LR8 {{ cr.in0_d1 }} next_plane ;;
    ADD LR7 LR7 {{ cr.in0_d0 }} ;;
lane_wrap:
    BLT.S LR7 LR9 reset_src ;;
    SUB LR7 LR7 LR9 ; INC LR10 1 ; B lane_wrap ;;
next_plane:
    SET LR8 CR0 ; INC LR11 1 ;;
    SET LR7 LR11 ; SET LR10 CR0 ; B lane_wrap ;;
reset_src:
    SET LR5 LR10 ; B advance ;;
