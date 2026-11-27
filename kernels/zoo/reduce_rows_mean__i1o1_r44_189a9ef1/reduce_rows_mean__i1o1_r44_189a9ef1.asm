{% set scale = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% macro accumulate(op) -%}
    MULT.RC.VE LR0 {{ scale }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{%- endmacro %}
{% macro load_next() -%}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;; ADD LR2 LR2 {{ cr.cb }}
{%- endmacro %}
{% macro store(ds) -%}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ;;
tile:
    SET LR2 LR1 ; SET LR3 CR1 ;;
    {{ load_next() }} ; BEQ CR0 {{ cr.before_last }} single ;;
    {{ accumulate('ACC.ADD.FIRST') }} ;;
    {{ load_next() }} ; BEQ CR1 {{ cr.before_last }} last ;;
spatial:
    {{ accumulate('ACC.ADD') }} ;;
    {{ load_next() }} ;;
    INC LR3 1 ; BLT.S LR3 {{ cr.loop_end }} spatial ;;
last:
    {{ accumulate('ACC.ADD') }} ;;
finish_tile:
    BEQ LR1 {{ cr.cbm1 }} tail ;;
    {{ store(cr.full) }}
    INC LR1 1 ; BEQ LR0 CR0 tile ;;
tail:
    {{ store(cr.tail) }}
    HALT ;;
single:
    {{ accumulate('ACC.ADD.FIRST') }} ; BEQ LR0 CR0 finish_tile ;;
