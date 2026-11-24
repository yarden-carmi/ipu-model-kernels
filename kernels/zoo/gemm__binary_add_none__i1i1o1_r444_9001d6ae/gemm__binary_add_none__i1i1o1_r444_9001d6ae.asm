{# Dot products accumulate directly into the packed pair's two lane ranges. #}
{% macro load(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro vec(slot, fmt, acc) %}MULT.RC.VE {{ slot }} CR1 0 LR0 {{ cr.full }}.L {{ fmt }}.L ; ACC.{{ acc }}{% endmacro %}
{% macro dot(slot, dest) %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM {{ dest }} {{ cr.full }}.L{% endmacro %}
{% macro store(ds) %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5{% endmacro %}
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SUB LR6 LR0 CR1 ; DEC LR5 1 ;;
    SUB LR10 LR1 {{ cr.s0_n }} ; SET LR9 {{ cr.s0_m }} ;;
pair:
    SUB LR4 LR0 CR1 ; SET LR11 CR0 ;;
    {{ load('LR0') }} ;;
    {{ vec('LR0', cr.qf_in0, 'ADD.FIRST') }} ; {{ load('LR1') }} ;;
    {{ vec('LR1', cr.qf_in0, 'ADD') }} ;;
point:
    SET LR4 CR1 ; SET LR7 {{ cr.chunks }} ;;
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SUB LR3 LR11 CR1 ; SET LR12 {{ cr.s0_n }} ;;
    {{ load('LR0') }} ;;
channel:
    {{ dot('LR0', 'LR3') }} ; {{ load('LR1') }} ; INC LR3 1 ; DEC LR12 1 ; BEQ LR12 CR1 last_low ;;
    {{ dot('LR1', 'LR3') }} ; {{ load('LR0') }} ; B channel ;;
last_low:
    {{ dot('LR1', 'LR3') }} ; INC LR2 1 ; DEC LR7 1 ;;
    BNE LR7 CR0 chunk ;;
    BEQ LR11 CR0 first_point ;;
    LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR0 ;;
    LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR1 ; INC LR6 1 ;;
    {{ vec('LR10', cr.qf_in1, 'ADD') }} ;;
    {{ store(cr.pair) }} ; INC LR5 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 pair ;;
    HALT ;;
first_point:
    LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR0 ; INC LR6 1 ; DEC LR9 1 ;;
    {{ vec('LR0', cr.qf_in1, 'ADD') }} ; BEQ LR9 CR0 tail ;;
    SET LR11 {{ cr.s0_n }} ; B point ;;
tail:
    {{ store(cr.single) }} ; INC LR5 1 ; HALT ;;
