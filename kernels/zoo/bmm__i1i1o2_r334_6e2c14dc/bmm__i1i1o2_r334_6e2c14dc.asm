{# A spans output M lanes; B supplies the scalar for the current column.
   Refill B during the MAC, then load the next A row in the branch word. #}
{% macro product(first, ahead, jump='') %}
    MULT.RC.VE LR9 LR3 0 LR9 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR5 LR5 {{ cr.ar }} ; ADD LR6 LR6 {{ cr.bc }} {% if ahead %}; LD.MULT R0 LR6 {{ cr.in1 }} ; DEC LR7 1{% endif %}{% if jump %} ; B {{ jump }}{% endif %} ;;
{% endmacro %}
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR9 CR0 ;;
group:
    SET LR11 {{ cr.out0_d1 }} ;;
head:
    SET LR2 {{ cr.n }} ; SET LR3 CR0 ; SET LR10 CR0 ;;
column:
    SET LR8 CR0 ;;
tile:
    ADD LR5 LR1 LR8 ; ADD LR6 LR4 LR10 ; SET LR7 {{ cr.k }} ;;
    LD.MULT R0 LR6 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR9 ; BEQ LR7 CR1 single ;;
    {{ product(true, true) }}
next_pair:
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR9 ; BNE LR7 CR1 reduce ;;
    {{ product(false, false) }}
store:
    INC LR8 1 ;;
    BEQ LR8 {{ cr.mc }} tail ;;
    {{ output('L') }}
    B tile ;;
tail:
    {{ output('H') }}
    DEC LR2 1 ;;
    BEQ LR2 CR0 next_head ;;
    INC.MODP2 LR3 CR1 7 ;;
    BNE LR3 CR0 column ;;
    INC LR10 1 ; B column ;;
next_head:
    DEC LR8 1 ;;
    SUB LR1 LR5 LR8 ; SUB LR4 LR6 LR10 ; DEC LR11 1 ;;
    BNE LR11 CR0 head ;;
    ADD LR1 LR1 LR12 ; ADD LR4 LR4 {{ cr.bgap }} ; DEC LR15 1 ;;
    BNE LR15 CR0 group ;;
    HALT ;;
reduce:
    {{ product(false, true, 'next_pair') }}
single:
    {{ product(true, false, 'store') }}
