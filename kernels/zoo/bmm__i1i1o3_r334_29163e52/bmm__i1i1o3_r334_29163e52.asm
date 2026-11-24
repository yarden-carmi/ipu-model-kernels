{# Each head occupies k consecutive rows in both inputs. A lane selects
   the query row; B supplies the entire output row in parallel. #}
{% macro product(first=false) %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }}
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ;;
head:
    SET LR3 CR0 ; ADD LR7 LR1 {{ cr.k }} ;;
row:
    SET LR5 LR1 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR0 ;;
    {{ product(true) }} ; INC LR5 1 ;;
    BEQ LR5 LR7 store ;;
reduce:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR0 ;;
    {{ product() }} ; INC LR5 1 ;;
    BNE LR5 LR7 reduce ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dstail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.m }} row ;;
    SET LR1 LR7 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.b }} head ;;
    HALT ;;
