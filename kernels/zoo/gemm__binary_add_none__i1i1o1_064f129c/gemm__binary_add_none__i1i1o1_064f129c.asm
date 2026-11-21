{% macro load(slot) %}
LD.MULT.CYCLIC LR8 {{ cr.w }} {{ slot }} ; INC LR8 1
{% endmacro %}
{% macro bias(slot, next, acc) %}
MULT.RC.VE {{ slot }} CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; {{ acc }} ; {{ load(next) }} ;;
{% endmacro %}
    SET LR1 {{ cr.width }} ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ;;
    DEC LR4 1 ;;
row:
    SET LR8 LR4 ; SET LR7 {{ cr.chunks }} ;;
    {{ load('LR0') }} ;;
    {{ bias('LR0', 'LR1', 'ACC.ADD.FIRST') }}
    {{ bias('LR1', 'LR0', 'ACC.ADD') }}
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR9 LR4 ;;
column:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; INC LR9 1 ; AGG.SUM LR9 {{ cr.full }}.L ; {{ load('LR1') }} ;;
    MULT.RC.VV LR1 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR9 {{ cr.full }}.L ; {{ load('LR0') }} ; BLT.S LR9 {{ cr.nm1 }} column ;;
    INC LR2 1 ; DEC LR7 1 ;;
    BNE LR7 CR0 chunk ;;
    LD.MULT R0 LR3 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.s0_m }} row ;;
    HALT ;;
