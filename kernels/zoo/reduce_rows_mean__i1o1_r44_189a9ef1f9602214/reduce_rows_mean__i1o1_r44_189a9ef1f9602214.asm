{% set scale = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% macro accumulate(op) -%}
    MULT.RC.VE LR0 {{ scale }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{%- endmacro %}
{% macro load_next() -%}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.cb }}
{%- endmacro %}
{% macro store(ds) -%}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ;;
tile:
    # LOAD sees the forwarded LR2, while the multiply sees the previous load.
    SET LR2 LR1 ; SET LR3 CR1 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BEQ CR0 {{ cr.before_last }} single ;;
    {{ accumulate('ACC.ADD.FIRST') }} ; {{ load_next() }} ; BEQ CR1 {{ cr.before_last }} last ;;
spatial:
    {{ accumulate('ACC.ADD') }} ; {{ load_next() }} ; INC LR3 1 ; BLT.S LR3 {{ cr.loop_end }} spatial ;;
last:
    BEQ LR1 {{ cr.cbm1 }} tail ;;
    {{ accumulate('ACC.ADD') }} ; {{ store(cr.full) }} ;;
    INC LR1 1 ; BEQ LR0 CR0 tile ;;
tail:
    {{ accumulate('ACC.ADD') }} ; {{ store(cr.tail) }} ; HALT ;;
single:
    BEQ LR1 {{ cr.cbm1 }} single_tail ;;
    {{ accumulate('ACC.ADD.FIRST') }} ; {{ store(cr.full) }} ;;
    INC LR1 1 ; BEQ LR0 CR0 tile ;;
single_tail:
    {{ accumulate('ACC.ADD.FIRST') }} ; {{ store(cr.tail) }} ; HALT ;;
