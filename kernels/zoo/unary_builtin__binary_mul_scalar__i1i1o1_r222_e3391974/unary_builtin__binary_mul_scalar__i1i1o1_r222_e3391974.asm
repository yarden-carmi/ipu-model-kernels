{% macro reciprocal(scale, slot) %}
    MULT.EE LR0 {{ scale }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_s0 }} {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ slot }} ;;
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
    INC LR3 128 ; INC LR4 1 ; INC LR8 5 ; LD.MULT R0 LR0 {{ cr.in1 }} ;;
    INC LR5 2 ; INC LR6 3 ; INC LR7 4 ; MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} LR8 ;;
    {{ reciprocal(cr.two, 'LR4') }}
    {{ reciprocal(cr.factor, 'LR0') }}
    ADD LR10 LR3 LR3 ; LD.MULT R1 LR8 {{ cr.s0 }} ;;
    ADD LR15 LR10 LR3 ;;

{% macro row(ds) %}
    {# Use the half-scale product normally. The boosted products recover
       large quotients when the reciprocal store runs out of range. #}
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
    {{ product(cr.two, 'ADD.FIRST', cr.qf_out0, 'LR0') }} ;;
    {{ product(cr.two, 'SUB', cr.qf_out0, 'LR10') }} ; ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
{% set chunks = (out0_d1 + 127) // 128 %}
{% set rows = out0_d0 * chunks %}
{% if rows <= 8 %}
{% for i in range(rows) %}
    {{ row(cr.tail if out0_d1 % 128 and (i + 1) % chunks == 0 else cr.full) }}
{% endfor %}
{% else %}
    SET LR12 {{ cr.tail }}.H ;;
{% if out0_d1 % 128 %}
    INC LR11 {{ chunks }} ;;
{% endif %}
next_row:
{% if out0_d1 % 128 %}
    INC LR2 1 ;;
    BEQ LR2 LR11 tail_row ;;
{% endif %}
    {{ row(cr.full) }}
{% if out0_d1 % 128 %}
    B next_row ;;
tail_row:
    {{ row(cr.tail) }}
    SET LR2 CR0 ;;
{% endif %}
    BLT.S LR1 LR12 next_row ;;
{% endif %}
    HALT ;;
