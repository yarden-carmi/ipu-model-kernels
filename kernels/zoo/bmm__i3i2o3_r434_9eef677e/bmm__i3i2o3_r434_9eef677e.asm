{# Accumulate one output row along N. An unaligned head reads a second
   physical RHS row only if its active lanes cross the boundary. #}
{% macro reduce(tag, split) %}
{{ tag }}:
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR6 ;;
{% if split %}
    LD.MULT.CYCLIC LR11 {{ cr.rhs_next }} LR9 ;;
{% endif %}
    MULT.RC.VE LR3 LR12 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ADD LR11 LR11 {{ cr.rhs_row_stride }} ;;
    INC LR12 1 ;;
    BLT.S LR12 {{ cr.k }} {{ tag }} ;;
{% endmacro %}
    INC LR9 128 ;;
group:
    SET LR2 LR10 ; SET LR3 CR0 ; SET LR4 {{ cr.in0_d1 }} ;;
normalize:
    BLT.S LR3 LR9 head ;;
    DEC LR3 128 ; INC LR2 1 ;;
    B normalize ;;
head:
    ADD LR14 LR3 {{ cr.n }} ; SET LR5 {{ cr.m }} ;;
row:
    LD.MULT R0 LR0 {{ cr.in0 }} ; SET LR11 LR2 ; SET LR12 CR0 ;;
    MULT.VE LR6 CR0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    BGT.S LR14 LR9 reduce_split ;;
    {{ reduce('reduce_single', false) }}
    B store ;;
    {{ reduce('reduce_split', true) }}
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ; DEC LR5 1 ;;
    BNE LR5 CR0 row ;;
    DEC LR4 1 ; ADD LR3 LR3 {{ cr.n }} ;;
    BNE LR4 CR0 normalize ;;
    ADD LR10 LR10 {{ cr.rhs_group_stride }} ; DEC LR15 1 ;;
    BNE LR15 CR0 group ;;
    HALT ;;
