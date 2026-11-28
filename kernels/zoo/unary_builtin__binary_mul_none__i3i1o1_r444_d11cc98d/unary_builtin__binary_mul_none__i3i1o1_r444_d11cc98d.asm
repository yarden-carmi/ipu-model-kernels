{% macro reciprocal(scale, slot) %}
    MULT.EE LR0 {{ scale }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_s0 }} {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ slot }} ;;
{% endmacro %}
{% macro product(scalar, acc, qf=cr.qf_out0, index='LR15') %}
    MULT.RC.VE {{ index }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ qf }}.L ; ACC.{{ acc }}
{% endmacro %}
{% macro save(act, slot) %}
    ; ACTIVATE.QUANTIZE {{ act }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.s0 }} {{ slot }}
{% endmacro %}
{% macro boost(acc, slot, cap=false) %}
    {{ product('LR0', acc) }} ;;
    {% if cap %} MULT.EE LR3 {{ cr.base_cap }} 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD ;; {% endif %}
    MULT.EE LR3 {{ cr.neg_cap }} 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.MAX {{ save('identity', slot) }} ;;
{% endmacro %}
{% macro merge(acc, slot) %}
    {{ product('CR1', acc, cr.qf_out0, 'LR0') }} ; LD.MULT.CYCLIC {{ slot }} {{ cr.s0 }} LR10 ;;
    {{ product(cr.neg_inv, 'MAX', cr.qf_out0, 'LR10') }} {{ save('relu', slot) }} ;;
{% endmacro %}
{# Transpose the mandated packed planes into channel rows. #}
    INC LR7 1 ; INC LR12 8 ; SET LR14 CR0 ;;
{% for i in range(24) %}
    ADD LR7 LR7 LR7 ;;
{% endfor %}
gather_y:
    SET LR3 CR0 ;;
gather_x:
{% for chunk in range((out0_d1 + 127) // 128) %}
    {% if chunk == 0 %}SET LR5 LR1 ;{% endif %} SET LR6 CR0 ;;
    SET LR2 LR5 ;;
    SET LR11 CR0 ; SET LR15 CR0 ;;
    INC LR15 {{ ([128, out0_d1 - chunk * 128] | min) - 1 }} ;;
    SUB LR11 LR0 LR7 ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
gather_channel_{{ chunk }}:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD8 LRD10 7 ; ADD LR11 LR11 LR7 ; INC LR6 1 ; INC LR5 {{ ((in0_d2 + 3) // 4) * ((in0_d3 * 4 + 127) // 128) }} ; BLT.S LR6 LR15 gather_channel_{{ chunk }} ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.{{ 'H' if chunk == ((out0_d1 + 127) // 128 - 1) else 'L' }} {{ cr.qf_out0 }}.L {{ cr.s0 }} LR12 ;;
    INC LR12 1 ;;
{% for sign, scale in [('pos', cr.zero_threshold), ('neg', cr.neg_cap)] %}
    SET LR5 LR2 ; SET LR6 CR0 ;;
    SUB LR11 LR0 LR7 ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
gather_sign_{{ chunk }}_{{ sign }}:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.EE LR4 {{ scale }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD8 LRD10 7 ; ADD LR11 LR11 LR7 ; INC LR6 1 ; INC LR5 {{ ((in0_d2 + 3) // 4) * ((in0_d3 * 4 + 127) // 128) }} ; BLT.S LR6 LR15 gather_sign_{{ chunk }}_{{ sign }} ;;
    ACTIVATE.QUANTIZE relu6 {{ cr.full }}.{{ 'H' if chunk == ((out0_d1 + 127) // 128 - 1) else 'L' }} {{ cr.qf_out0 }}.L {{ cr.s0 }} LR12 ;;
    LD.MULT R0 LR12 {{ cr.s0 }} ;;
    MULT.VE LR0 {{ cr.factor }} 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE relu6 {{ cr.full }}.{{ 'H' if chunk == ((out0_d1 + 127) // 128 - 1) else 'L' }} {{ cr.qf_out0 }}.L {{ cr.s0 }} LR12 ;;
    INC LR12 1 ;;
{% endfor %}
    SET LR6 LR12 ; SET LR11 LR12 ;;
    DEC LR6 2 ; DEC LR11 1 ;;
    LD.MULT.CYCLIC LR6 {{ cr.s0 }} LR0 ;;
    LD.MULT R0 LR11 {{ cr.s0 }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ cr.full }}.{{ 'H' if chunk == ((out0_d1 + 127) // 128 - 1) else 'L' }} {{ cr.qf_out0 }}.L {{ cr.s0 }} LR6 ;;
{% endfor %}
    INC LR3 1 ; INC LR4 1 ; SET LR15 CR0 ;;
    INC LR15 {{ in0_d3 }} ;;
    BLT.S LR3 LR15 gather_x ;;
    INC LR13 1 ; INC LR14 1 ; SET LR15 CR0 ;;
    INC LR15 4 ;;
    BLT.S LR14 LR15 gather_same_block ;;
    SET LR14 CR0 ; SET LR4 CR0 ; INC LR1 1 ;;
gather_same_block:
    SET LR15 CR0 ;;
    INC LR15 {{ in0_d2 }} ;;
    BLT.S LR13 LR15 gather_y ;;
{% for i in range(1, 16) %}
    SET LR{{ i }} CR0 ;;
{% endfor %}
{% for i in range((out0_d0 * out0_d2 * out0_d3) // 128) %}
    INC LR14 128 ;;
{% endfor %}
    INC LR14 {{ (out0_d0 * out0_d2 * out0_d3) % 128 }} ;;
    INC LR3 128 ; INC LR4 1 ; INC LR8 5 ;;
    INC LR5 2 ; INC LR6 3 ; INC LR7 4 ; MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.s0 }} LR8 ;;
    ADD LR10 LR3 LR3 ; LD.MULT R1 LR8 {{ cr.s0 }} ;;
    ADD LR15 LR10 LR3 ; INC LR12 6 ; INC LR13 7 ;;

{% macro row(ds) %}
    ADD LR11 LR1 LR1 ;;
    ADD LR11 LR11 LR1 ;;
    INC LR11 8 ;;
    LD.MULT.CYCLIC LR11 {{ cr.s0 }} LR15 ;;
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
    INC LR11 1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.s0 }} LR10 ;;
    {{ product('LR0', 'ADD', cr.qf_out0, 'LR10') }} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
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
{% for slot in ['LR0', 'LR4', 'LR12'] %}
    LD.MULT R0 {{ slot }} {{ cr.s0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.s0 }} {{ slot }} ;;
{% endfor %}
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
