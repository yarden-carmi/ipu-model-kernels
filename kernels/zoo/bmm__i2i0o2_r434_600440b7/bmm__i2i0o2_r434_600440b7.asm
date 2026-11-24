{# A supplies one M tile; the RHS scalar is the current group lane. #}
{% macro reduce_step(first) %}
    LD.MULT R0 LR8 {{ cr.in1 }} ; DEC LR9 1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR15 ; ADD LR8 LR8 {{ cr.in1_d2 }} ;;
    MULT.RC.VE LR15 LR1 0 LR15 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR7 LR7 {{ cr.a_tiles }} {% if not first %}; BNE LR9 CR0 reduce {% endif %};;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR15 CR0 ;;
group:
    SET LR3 {{ cr.rhs_start }} ; SET LR4 LR12 ;;
head:
    SET LR5 {{ cr.n }} ;;
column:
    SET LR6 LR2 ; SET LR10 LR13 ;;
tile:
    SET LR7 LR6 ; SET LR8 LR3 ; SET LR9 {{ cr.k }} ;;
    {{ reduce_step(true) }}
    BEQ LR9 CR0 write ;;
reduce:
    {{ reduce_step(false) }}
write:
    DEC LR10 1 ;;
    BEQ LR10 CR0 tail ;;
    {{ store(cr.full_ds) }}
    INC LR6 1 ; B tile ;;
tail:
    {{ store(cr.tail_ds) }}
    INC LR3 1 ; DEC LR5 1 ;;
    BNE LR5 CR0 column ;;
    ADD LR2 LR2 LR14 ; DEC LR4 1 ;;
    BNE LR4 CR0 head ;;
    INC LR1 1 ; DEC LR11 1 ;;
    BNE LR11 CR0 group ;;
    HALT ;;
