{% macro reciprocal(scale, slot) %}
    MULT.EE LR0 {{ scale }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_s0 }} {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ slot }} ;;
{% endmacro %}
{% macro product(scalar, acc, qf=cr.qf_in0, index='LR15') %}
    MULT.RC.VE {{ index }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ qf }}.L ; ACC.{{ acc }}
{% endmacro %}
{% macro save(act, slot) %}
    ; ACTIVATE.QUANTIZE {{ act }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.s0 }} {{ slot }}
{% endmacro %}
{% macro boost(acc, slot, cap=false) %}
    {{ product('LR0', acc) }} ;;
    {% if cap %} MULT.EE LR3 {{ cr.base_cap }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;; {% endif %}
    MULT.EE LR3 {{ cr.neg_cap }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.MAX {{ save('identity', slot) }} ;;
{% endmacro %}
{% macro merge(acc, slot) %}
    {{ product('CR1', acc, cr.qf_out0, 'LR0') }} ; LD.MULT.CYCLIC {{ slot }} {{ cr.s0 }} LR10 ;;
    {{ product(cr.neg_inv, 'MAX', cr.qf_out0, 'LR10') }} {{ save('relu', slot) }} ;;
{% endmacro %}
    INC LR3 128 ; INC LR4 1 ; INC LR8 5 ;;
    INC LR5 2 ; INC LR6 3 ; INC LR7 4 ; MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR8 ;;
    ADD LR10 LR3 LR3 ; LD.MULT R1 LR8 {{ cr.s0 }} ;;
    ADD LR15 LR10 LR3 ; INC LR12 6 ; INC LR13 7 ;;

{% macro row(ds) %}
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR15 ;;
    LD.MULT R0 LR4 {{ cr.s0 }} ;;
    {{ product('LR0', 'ADD.FIRST') }} {{ save('identity', 'LR7') }} ; LD.MULT R0 LR0 {{ cr.s0 }} ;;
    {{ boost('ADD.FIRST', 'LR6') }}
    {{ boost('SUB.FIRST', 'LR5', true) }}
    LD.MULT.CYCLIC LR7 {{ cr.s0 }} LR0 ;;
    {{ merge('ADD.FIRST', 'LR5') }}
    {{ merge('SUB.FIRST', 'LR6') }}
    LD.MULT.CYCLIC LR5 {{ cr.s0 }} LR0 ;;
    LD.MULT.CYCLIC LR6 {{ cr.s0 }} LR10 ;;
    {{ product(cr.two, 'ADD.FIRST', cr.qf_out0, 'LR0') }} ; LD.MULT R0 LR12 {{ cr.s0 }} ;;
    {{ product(cr.two, 'SUB', cr.qf_out0, 'LR10') }} ;;
    {{ product('LR0', 'ADD') }} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

pixel:
    LD.MULT R0 LR9 {{ cr.in1 }} ;;
    {{ reciprocal(cr.two, 'LR4') }}
    {{ reciprocal(cr.factor, 'LR0') }}
    {# Only exact zeros can leave the boosted reciprocal above the threshold.
       Restore IEEE infinity for those zeros without altering finite NX8 quotients. #}
    LD.MULT R0 LR0 {{ cr.s0 }} ;;
{% for slot, acc in [('LR12', 'ADD.FIRST'), ('LR13', 'SUB.FIRST')] %}
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ acc }} ;;
    MULT.EE LR3 {{ cr.zero_threshold }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ slot }} ;;
{% endfor %}
    LD.MULT R0 LR12 {{ cr.s0 }} ;;
    MULT.EE LR0 {{ cr.factor }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR13 {{ cr.s0 }} ;;
    MULT.EE LR0 {{ cr.factor }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR12 ;;
{% set chunks = (out0_d1 + 127) // 128 %}
{% if chunks <= 8 %}
{% for i in range(chunks) %}
    {{ row(cr.full ~ ('.H' if i + 1 == chunks else '.L')) }}
{% endfor %}
{% else %}
    SET LR11 LR1 ;;
    INC LR11 {{ chunks - 1 }} ;;
channel:
    {{ row(cr.full ~ '.L') }}
    BLT.S LR1 LR11 channel ;;
    {{ row(cr.full ~ '.H') }}
{% endif %}
    INC LR9 1 ;;
    BLT.S LR9 LR14 pixel ;;
    HALT ;;
