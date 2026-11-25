{# Each A row is one M tile for one key and head. Each B row holds
   a key chunk of one column; reuse it for up to 128 scalar broadcasts. #}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR15 CR0 ;;
group:
    SET LR6 {{ cr.in0_d1 }} ;;
head:
    SET LR7 {{ cr.n }} ;;
column:
    SET LR9 LR4 ; SET LR10 {{ cr.oc }} ;;
tile:
    SET LR11 LR9 ; SET LR12 LR5 ; SET LR13 {{ cr.k }} ;;
    MULT.RC.VE LR15 CR0 0 LR15 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
chunk:
    LD.MULT R0 LR12 {{ cr.in1 }} ; SET LR14 CR0 ;;
    INC LR12 1 ;;
key:
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR15 ; DEC LR13 1 ;;
    MULT.RC.VE LR15 LR14 0 LR15 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR11 LR11 {{ cr.a_key }} ;;
    BEQ LR13 CR0 result ; INC.MODP2 LR14 CR1 7 ;;
    BNE LR14 CR0 key ;;
    B chunk ;;
result:
    BEQ LR10 CR1 tail ;;
    {{ store('L') }}
    B tile ; INC LR0 1 ; INC LR9 1 ; DEC LR10 1 ;;
tail:
    {{ store('H') }}
    ADD LR5 LR5 {{ cr.bc }} ; DEC LR7 1 ; INC LR0 1 ;;
    BNE LR7 CR0 column ;;
    ADD LR4 LR4 {{ cr.ac }} ; DEC LR6 1 ;;
    BNE LR6 CR0 head ;;
    ADD LR4 LR4 LR1 ; SUB LR5 LR5 LR2 ; DEC LR3 1 ;;
    BNE LR3 CR0 group ;;
    HALT ;;
