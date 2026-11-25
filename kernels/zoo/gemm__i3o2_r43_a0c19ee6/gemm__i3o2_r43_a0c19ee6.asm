{# Two adjacent reduction chunks share a row. Keep both packed halves of K
   resident: the full output tile uses outer products, and the partial tile
   uses two lane-parallel dot products per output instead of padded vectors. #}
{% macro next_weight() %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1
{%- endmacro %}
{% macro outer() %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
{% macro dot(bank) %}
    MULT.RC.VV LR0 {{ bank }} 0 LR0 {{ cr.dot }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.dot }}.L
{%- endmacro %}
{% macro bias() %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5
{%- endmacro %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; DEC LR5 1 ; SET LR10 {{ cr.rows }} ; INC LR7 127 ;;
row:
    LD.MULT R0 LR5 {{ cr.in0 }} ; INC LR5 1 ; SET LR3 CR0 ;;
    LD.MULT R1 LR2 {{ cr.in0 }} ; ADD LR2 LR5 CR1 ; DEC LR3 1 ;;
    {{ bias() }} ; {{ next_weight() }} ;;
first_bank:
    {{ outer() }} ; {{ next_weight() }} ; INC LR3 1 ; BLT.S LR3 {{ cr.first_end }} first_bank ;;
    {# Switch banks as the first bank's last multiply retires. #}
    {{ outer() }} ; {{ next_weight() }} ; ADD LR3 LR7 CR1 ;;
{% if chunk > 2 %}
second_bank:
    {{ outer() }} ; {{ next_weight() }} ; INC LR3 1 ; BLT.S LR3 {{ cr.second_end }} second_bank ;;
{% endif %}
    {{ outer() }} ; {{ next_weight() }} ; INC LR3 1 ; {{ store(cr.full) }} ;;
    {{ bias() }} ; {{ next_weight() }} ; SUB LR3 LR0 CR1 ; DEC LR10 1 ;;
tail_first:
    {{ dot('R0') }} ; {{ next_weight() }} ; INC LR3 1 ; BEQ LR3 {{ cr.tail_end }} tail_last ;;
    {{ dot('R1') }} ; {{ next_weight() }} ; B tail_first ;;
tail_last:
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; SET LR4 CR0 ; {{ dot('R1') }} ; INC LR5 1 ; {{ store(cr.tail) }} ; BNE LR10 CR0 row ;;
    HALT ;;
