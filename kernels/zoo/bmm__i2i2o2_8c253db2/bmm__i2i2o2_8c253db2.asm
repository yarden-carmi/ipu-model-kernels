{# A and the output share the M lane axis. Broadcast each B scalar
   across one A tile and retain the sum in FP32 until the final store. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR10 CR0 ; SET LR13 CR0 ;;
head:
    SET LR12 CR0 ;;
column:
    SET LR6 CR0 ; SET LR14 LR2 ;;
tile:
    SET LR7 LR14 ; SET LR8 LR1 ; SET LR9 CR0 ;;
{% macro product(first) %}
    LD.MULT R0 LR8 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR7 LR7 {{ cr.mc }} ; ADD LR8 LR8 {{ cr.brows }} ; INC LR9 1 ;;
{% endmacro %}
    {{ product(true) }}
    B check_k ;;
inner:
    {{ product(false) }}
check_k:
    BLT.S LR9 {{ cr.k }} inner ;;
    INC LR6 1 ;;
    BEQ LR6 {{ cr.mc }} tail ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ;;
{% endmacro %}
    {{ output('L') }}
    INC LR14 1 ;;
    B tile ;;
tail:
    {{ output('H') }}
    INC LR12 1 ; INC.MODP2 LR3 CR1 7 ;;
    BNE LR3 CR0 same_chunk ;;
    INC LR1 1 ;;
same_chunk:
    BLT.S LR12 {{ cr.n }} column ;;
    INC LR13 1 ; INC LR4 1 ;;
    BGE.S LR13 {{ cr.b }} done ;;
    SUB LR2 LR7 LR6 ;;
    INC LR2 1 ;;
    BNE LR4 LR15 head ;;
    ADD LR1 LR5 LR11 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    SET LR5 LR1 ;;
    B head ;;
done:
    HALT ;;
