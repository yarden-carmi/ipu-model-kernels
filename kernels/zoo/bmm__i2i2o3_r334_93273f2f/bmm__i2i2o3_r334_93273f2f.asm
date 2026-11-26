{# Align one RHS head into a reusable panel. Keep both LHS rows of a pair
   in the cyclic file so each RHS load produces two output elements. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR15 CR0 ; SET LR13 CR0 ;;
    INC LR15 128 ;;
group:
    SET LR3 LR1 ; SET LR4 LR2 ; SET LR5 CR0 ;;
    SET LR6 {{ cr.pair_heads }}.H ;;
head:
    SET LR7 LR4 ; SET LR8 CR0 ; SET LR9 {{ cr.widths }}.H ;;
pack_rhs:
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR5 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR8 ;;
    INC LR8 1 ; ADD LR7 LR7 {{ cr.strides }}.H ; DEC LR9 1 ; BNE LR9 CR1 pack_rhs ;;
    SET LR7 LR3 ; SET LR10 {{ cr.pair_heads }}.L ; ADD LR12 LR5 LR15 ;;
pair:
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ;;
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR15 ; ADD LR7 LR7 {{ cr.strides }}.L ;;
    SET LR8 CR0 ; SET LR9 {{ cr.widths }}.H ; SET LR11 {{ cr.widths }}.H ;;
    ADD LR7 LR7 {{ cr.strides }}.L ;;
column:
    LD.MULT R0 LR8 {{ cr.panel }} ;;
{% macro dot(lane, slot) %}
    MULT.RC.VV {{ lane }} R0 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST {{ slot }} {{ cr.active }}.L
{%- endmacro %}
    {{ dot('LR5', 'LR8') }} ;;
    {{ dot('LR12', 'LR11') }} ;;
    INC LR8 1 ; INC LR11 1 ; DEC LR9 1 ; BNE LR9 CR1 column ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ; DEC LR10 1 ; BNE LR10 CR1 pair ;;
    DEC LR6 1 ; BEQ LR6 CR1 next_group ;;
    ADD LR5 LR5 {{ cr.widths }}.L ;;
    BLT.S LR5 LR15 head ;;
    DEC LR5 128 ; INC LR3 1 ; INC LR4 1 ; B head ;;
next_group:
    ADD LR1 LR1 {{ cr.group_a }} ; ADD LR2 LR2 {{ cr.group_b }} ; DEC LR14 1 ; BNE LR14 CR1 group ;;
    HALT ;;
