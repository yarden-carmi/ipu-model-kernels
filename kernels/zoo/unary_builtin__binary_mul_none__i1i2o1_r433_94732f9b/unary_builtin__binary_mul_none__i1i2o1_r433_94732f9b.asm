{% macro ve(index, scalar, acc) %}
    MULT.VE {{ index }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ acc }}
{% endmacro %}
{% macro rc(index, scalar, acc, qf=cr.qf_in0) %}
    MULT.RC.VE {{ index }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ qf }}.L ; ACC.{{ acc }}
{% endmacro %}
{% macro scratch(act, slot, qf=cr.qf_in0) %}
    ; ACTIVATE.QUANTIZE {{ act }} {{ cr.full }}.L {{ qf }}.L {{ cr.s0 }} {{ slot }}
{% endmacro %}
{% macro one(acc) %}
    MULT.EE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ acc }}
{% endmacro %}
    INC LR4 1 ; INC LR5 2 ; INC LR6 3 ;;
    INC LR7 4 ; INC LR10 5 ; INC LR12 6 ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR6 ;;
    INC LR3 128 ; LD.MULT R1 LR6 {{ cr.s0 }} ;;
pixel:
    {# One element of the handed 128-wide denominator row is broadcast over the channels. #}
    LD.MULT R0 LR9 {{ cr.in1 }} ;;
    MULT.EE LR11 {{ cr.factor }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_s0 }} {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.s0 }} ;;
    {{ ve('LR0', 'CR1', 'SUB.FIRST') }} ;;
    {{ ve('LR0', 'CR1', 'MAX') }} {{ scratch('identity', 'LR4') }} ;;
    {{ ve('LR0', cr.large, 'ADD.FIRST') }} {{ scratch('relu6', 'LR5') }} ;;
    {{ one('ADD.FIRST') }} ; LD.MULT R0 LR5 {{ cr.s0 }} ;;
    {{ ve('LR0', 'CR1', 'SUB') }} {{ scratch('relu', 'LR5') }} ;;
    {{ one('ADD.FIRST') }} ; LD.MULT R0 LR5 {{ cr.s0 }} ;;
    {{ ve('LR0', 'CR1', 'SUB') }} ;;
    {{ ve('LR0', 'CR1', 'SUB') }} {{ scratch('identity', 'LR5') }} ;;
{% macro row(ds) %}
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    {{ rc('LR0', cr.factor, 'SUB.FIRST') }} ;;
    {{ rc('LR0', cr.factor, 'MAX') }} {{ scratch('identity', 'LR7') }} ; LD.MULT R0 LR4 {{ cr.s0 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.s0 }} LR3 ;;
    {# Clamp the negative magnitude before storing, so overflow cannot set the wrong row scale. #}
    {{ rc('LR3', 'LR0', 'SUB.FIRST') }} ;;
    MULT.EE LR3 {{ cr.neg_cap }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.MAX ;;
    MULT.EE LR3 {{ cr.eps }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB {{ scratch('identity', 'LR7') }} ;;
    {{ rc('LR0', cr.factor, 'ADD.FIRST') }} {{ scratch('identity', 'LR10') }} ;;
    LD.MULT.CYCLIC LR10 {{ cr.s0 }} LR0 ;;
    {{ rc('LR0', cr.large, 'ADD.FIRST') }} {{ scratch('relu6', 'LR10') }} ;;
    {{ one('ADD.FIRST') }} ; LD.MULT.CYCLIC LR10 {{ cr.s0 }} LR0 ;;
    {{ rc('LR0', 'CR1', 'SUB') }} {{ scratch('relu', 'LR10') }} ;;
    LD.MULT.CYCLIC LR10 {{ cr.s0 }} LR0 ;;
    LD.MULT R0 LR5 {{ cr.s0 }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ;;
    {{ rc('LR0', 'LR0', 'ADD') }} ;;
    {{ rc('LR0', 'LR0', 'ADD') }} {{ scratch('identity', 'LR12') }} ;;
    LD.MULT R0 LR12 {{ cr.s0 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.s0 }} LR3 ;;
    MULT.RC.VV LR3 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    {{ ve('LR0', cr.undo_eps, 'ADD') }} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
{% set chunks = (out0_d1 + 127) // 128 %}
{% if chunks <= 16 %}
{% for i in range(chunks) %}
    {{ row(cr.full ~ ('.H' if i + 1 == chunks else '.L')) }}
{% endfor %}
{% else %}
    SET LR2 LR1 ;;
    INC LR2 {{ chunks - 1 }} ;;
channel:
    {{ row(cr.full ~ '.L') }}
    BLT.S LR1 LR2 channel ;;
    {{ row(cr.full ~ '.H') }}
{% endif %}
    INC.MODP2 LR11 LR4 7 ; INC LR8 1 ;;
    BNE LR11 LR0 advance ;;
    INC LR9 1 ;;
advance:
    BLT.S LR8 LR14 pixel ;;
    HALT ;;
