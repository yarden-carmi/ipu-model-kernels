{# Both operands run along K. Each dot writes one lane of the output tile. #}
    SET LR0 {{ cr.out_prev }} ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 {{ cr.b }} ;;
batch:
    SET LR4 {{ cr.m }} ; SET LR15 CR0 ;;
row:
    SET LR5 LR2 ; SET LR6 {{ cr.n }} ; SET LR8 CR0 ;;
{# Multiply reads the old cyclic row; the load sees the incremented row pointer. #}
{% macro dot(first, more, branch='') %}
    MULT.RC.VV LR15 R0 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR8 {{ cr.ds }}.L ; INC LR9 1 ; INC LR10 1{% if more %} ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR15{% endif %}{% if branch %} ; B {{ branch }}{% endif %} ;;
{% endmacro %}
column:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR15 ; SET LR9 LR1 ; SET LR10 LR5 ; SET LR11 {{ cr.chunks }} ;;
    LD.MULT R0 LR10 {{ cr.in1 }} ; DEC LR11 1 ; BEQ LR11 CR1 single ;;
    {{ dot(true, true) }}
reduce:
    LD.MULT R0 LR10 {{ cr.in1 }} ; DEC LR11 1 ; BEQ LR11 CR1 last ;;
    {{ dot(false, true, 'reduce') }}
single:
    {{ dot(true, false, 'column_done') }}
last:
    {{ dot(false, false) }}
column_done:
    SET LR5 LR10 ; DEC LR6 1 ; INC.MODP2 LR8 CR1 7 ; BEQ LR6 CR1 tail ;;
    BNE LR8 CR0 column ;;
{# AAQ sees the incremented offset. A full tile has already wrapped LR8. #}
{% macro store(half, control) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ; INC LR0 1 ; {{ control }} ;;
{% endmacro %}
    {{ store('L', 'B column') }}
tail:
    {{ store('H', 'ADD LR1 LR1 ' ~ cr.chunks ~ ' ; DEC LR4 1 ; BNE LR4 CR1 row') }}
    ADD LR2 LR2 {{ cr.rhs_batch }} ; DEC LR3 1 ; BNE LR3 CR1 batch ;;
    HALT ;;
