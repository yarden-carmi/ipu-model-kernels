{# Aggregate a contiguous horizontal span directly into one output lane. #}
{% macro reduce(index, ds, first='') -%}
MULT.VE {{ index }} CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ first }} LR8 {{ ds }}.L
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    SET LR6 CR0 ;;
plane:
    SUB LR2 LR0 {{ cr.padding }} ; SET LR3 CR0 ; SET LR4 LR5 ;;
out_y:
    ADD LR10 LR2 {{ cr.k }} ; SET LR9 LR2 ; SUB LR7 LR0 {{ cr.padding }} ;;
    SET LR8 CR0 ; BGE.S LR9 CR0 top_ok ;;
    SET LR9 CR0 ;;
top_ok:
    BLT.S LR10 {{ cr.in0_d2 }} bottom_ok ;;
    SET LR10 {{ cr.in0_d2 }} ;;
bottom_ok:
    ADD LR9 LR9 LR1 ; ADD LR10 LR10 LR1 ;;
out_x:
    ADD LR13 LR7 {{ cr.k }} ; SET LR11 LR9 ;;
    BLT.S LR7 CR0 edge ;;
    BLT.S {{ cr.in0_d3 }} LR13 edge ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    {{ reduce('LR7', cr.ds_win, '.FIRST') }} ; INC LR11 1 ;;
    BGE.S LR11 LR10 next_x ;;
interior_y:
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    {{ reduce('LR7', cr.ds_win) }} ; INC LR11 1 ;;
    BLT.S LR11 LR10 interior_y ;;
    BEQ LR0 CR0 next_x ;;
edge:
    BLT.S LR13 {{ cr.in0_d3 }} edge_seed ;;
    SET LR13 {{ cr.in0_d3 }} ;;
edge_seed:
    SET LR12 LR7 ; LD.MULT R0 LR11 {{ cr.in0 }} ;;
    BGE.S LR12 CR0 edge_first ;;
    SET LR12 CR0 ;;
edge_first:
    {{ reduce('LR12', cr.ds_one, '.FIRST') }} ;;
edge_x:
    {{ reduce('LR12', cr.ds_one) }} ;;
    INC LR12 1 ;;
    BLT.S LR12 LR13 edge_x ;;
    INC LR11 1 ;;
    BGE.S LR11 LR10 next_x ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ; SET LR12 LR7 ;;
    BGE.S LR12 CR0 edge_x ;;
    SET LR12 CR0 ; BEQ LR0 CR0 edge_x ;;
next_x:
    INC LR8 1 ; ADD LR7 LR7 {{ cr.stride }} ;;
    BLT.S LR8 {{ cr.out0_d3 }} out_x ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR3 1 ; ADD LR2 LR2 {{ cr.stride }} ; ADD LR4 LR4 LR15 ;;
    BLT.S LR3 {{ cr.out0_d2 }} out_y ;;
    ADD LR1 LR1 {{ cr.in0_d2 }} ; INC LR5 1 ; INC LR6 1 ;;
    BGE.S LR1 LR14 done ;;
    BLT.S LR6 LR15 plane ;;
    SUB LR5 LR4 LR15 ; SET LR6 CR0 ;;
    INC LR5 1 ; BEQ LR0 CR0 plane ;;
done:
    HALT ;;
