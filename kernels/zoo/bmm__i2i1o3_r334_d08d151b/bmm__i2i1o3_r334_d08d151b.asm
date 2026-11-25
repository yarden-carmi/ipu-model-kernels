{# LR8 selects a packed key row; LR9 selects its first or second vector.
   LR15 indexes the query window across R0 and R1. #}
{% macro mac(first, tag) %}
    LD.MULT.CYCLIC LR8 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR9 LR15 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; BNE LR9 CR0 {{ tag }}_odd ;;
    SET LR9 {{ cr.packing }}.L ; B {{ tag }}_next ;;
{{ tag }}_odd:
    SET LR9 CR0 ; INC LR8 1 ;;
{{ tag }}_next:
    INC LR15 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR1 128 ; SET LR3 CR0 ; SET LR4 CR0 ;;
group:
    SET LR5 {{ cr.outer }}.H ; SET LR6 LR2 ; SET LR7 CR0 ;;
    SET LR8 CR0 ; SET LR9 LR3 ;;
b_group_row:
    BLT.S LR9 LR1 b_group_tail ;;
    DEC LR9 128 ; INC LR8 64 ; B b_group_row ;;
b_group_tail:
    BEQ LR9 CR0 head ;;
    BEQ LR9 CR1 b_group_odd ;;
    DEC LR9 2 ; INC LR8 1 ; B b_group_tail ;;
b_group_odd:
    SET LR9 {{ cr.packing }}.L ;;
head:
    SET LR10 LR8 ; SET LR12 LR9 ; SET LR11 LR6 ;;
    SET LR13 {{ cr.outer }}.L ;;
row:
    LD.MULT R0 LR11 {{ cr.in0 }} ; ADD LR15 LR11 CR1 ; BLE.S LR7 {{ cr.packing }}.H reduce_setup ;;
    LD.MULT R1 LR15 {{ cr.in0 }} ;;
reduce_setup:
    SET LR8 LR10 ; SET LR9 LR12 ; SET LR15 LR7 ;;
    ADD LR1 LR7 {{ cr.sizes }}.L ;;
    {{ mac(true, 'first') }}
    BEQ LR15 LR1 store ;;
reduce:
    {{ mac(false, 'more') }}
    BLT.S LR15 LR1 reduce ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; ADD LR11 LR11 {{ cr.a_rows }} ; DEC LR13 1 ;;
    BNE LR13 CR0 row ;;
    SET LR1 CR0 ; DEC LR5 1 ; ADD LR7 LR7 {{ cr.sizes }}.L ;;
    INC LR1 128 ; BEQ LR5 CR0 group_done ;;
    BLT.S LR7 LR1 head ;;
    DEC LR7 128 ; INC LR6 1 ; B head ;;
group_done:
    ADD LR2 LR2 {{ cr.a_group }} ; ADD LR3 LR3 {{ cr.b_group }} ; DEC LR14 1 ;;
    BNE LR14 CR0 group ;;
    HALT ;;
