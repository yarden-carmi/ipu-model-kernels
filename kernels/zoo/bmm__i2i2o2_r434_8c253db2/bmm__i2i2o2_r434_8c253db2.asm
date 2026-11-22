{# Each A row contains one M tile for one reduction index. B stays in
   its producer layout: the scalar cursor crosses interleaved heads. #}
{% macro step(first, again='') %}
    LD.MULT R0 LR9 {{ cr.in1 }} ; DEC LR14 1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR15 ; ADD LR9 LR9 {{ cr.bc }} ;;
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR11 LR11 {{ cr.ac }}{% if again %} ; BNE LR14 CR0 {{ again }}{% endif %} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR10 CR0 ;;
    SET LR15 CR0 ;;
group:
    SET LR2 LR1 ; SET LR5 CR0 ; SET LR4 LR6 ;;
head:
    SET LR8 {{ cr.n }} ;;
column:
    SET LR12 LR10 ; SET LR13 {{ cr.oc }} ;;
tile:
    SET LR11 LR12 ; SET LR9 LR2 ; SET LR14 {{ cr.k }} ;;
    {{ step(true) }}
    BEQ LR14 CR0 store ;;
reduce:
    {{ step(false, 'reduce') }}
store:
    DEC LR13 1 ;;
    BEQ LR13 CR0 tail ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ; INC LR12 1 ;;
    BNE LR13 CR0 tile ; INC LR0 1 ;;
tail:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ; INC.MODP2 LR5 CR1 7 ; DEC LR8 1 ;;
    BNE LR5 CR0 same_row ; INC LR0 1 ;;
    INC LR2 1 ;;
same_row:
    BNE LR8 CR0 column ;;
    ADD LR10 LR10 {{ cr.a_head }} ; DEC LR4 1 ;;
    BNE LR4 CR0 head ;;
    ADD LR1 LR1 LR7 ; DEC LR3 1 ;;
    BNE LR3 CR0 group ;;
    HALT ;;
