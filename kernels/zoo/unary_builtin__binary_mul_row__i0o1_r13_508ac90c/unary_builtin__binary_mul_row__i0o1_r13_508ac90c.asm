{% set chunks = (out0_d1 + 127) // 128 %}
{% set short = out0_d2 <= 32 and chunks <= 32 %}
{% set single = short and out0_d0 == 1 %}
{% set scalar = 'LR0' if in0_d0 == 1 else 'LR1' %}
{% macro product(ds, next=false) %}
    MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ ds }} {{ cr.qf_numerator }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ; INC LR4 1 {% if next %}; LD.MULT.CYCLIC LR2 {{ cr.numerator }} LR0 {% endif %}
{% endmacro %}

    LD.MULT R0 LR0 {{ cr.in0 }} ; DEC LR4 1 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.ds_pair }}.H {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_s0 }} {{ cr.ds_pair }}.H {{ cr.qf_numerator }}.L {{ cr.s0 }} LR0 {% if single %}; LD.MULT.CYCLIC LR2 {{ cr.numerator }} LR0 {% endif %} ;;
    LD.MULT R0 LR0 {{ cr.s0 }} ;;
{% if not single %}
plane:
    SET LR1 CR0 ; LD.MULT.CYCLIC LR2 {{ cr.numerator }} LR0 ;;
{% endif %}
{% if short %}
    {% for c in range(out0_d2) %}
        {% for i in range(chunks) %}
    {{ product(cr.ds_pair ~ '.L' if i == chunks - 1 else 'CR15.L', i < chunks - 1 or c + 1 < out0_d2) }} {% if i == chunks - 1 and c + 1 < out0_d2 and in0_d0 > 1 %}; INC LR1 1 {% endif %} ;;
        {% endfor %}
    {% endfor %}
{% else %}
column:
    {% if chunks <= 32 %}
        {% for i in range(chunks - 1) %}
    {{ product('CR15.L', true) }} ;;
        {% endfor %}
    {% else %}
    SET LR3 LR2 ;;
    INC LR3 {{ chunks - 2 }} ;;
chunk:
    {{ product('CR15.L', true) }} ; BLT.S LR2 LR3 chunk ;;
    {% endif %}
    {{ product(cr.ds_pair ~ '.L') }} ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.out0_d2 }} next_column ;;
    BLT.S LR2 {{ cr.rows }} plane ;;
    HALT ;;
next_column:
    LD.MULT.CYCLIC LR2 {{ cr.numerator }} LR0 ; B column ;;
{% endif %}
{% if short %}
    {% if not single %}
    BLT.S LR2 {{ cr.rows }} plane ;;
    {% endif %}
    HALT ;;
{% endif %}
