{% set chunks = (out0_d2 + 127) // 128 %}
{% set short = in1_d1 <= 32 and chunks <= 32 and in1_d1 * chunks <= 128 %}
{% macro product(ds, next=false) %}
    MULT.RC.VE LR0 LR0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ; INC LR4 1 {% if next %}; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 {% endif %}
{% endmacro %}
{% macro inverse(index) %}
    MULT.EE LR0 CR1 0 LR0 {{ cr.ds_pair }}.H {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_s0 }} {{ cr.ds_pair }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ index }}
{% endmacro %}

// Quantize each reciprocal separately so it gets its own row scale.
{% if short %}
    DEC LR4 1 ; LD.MULT R0 LR0 {{ cr.in1 }} ;;
    {% for i in range(in1_d1) %}
    {{ inverse('LR1') }} {% if i + 1 < in1_d1 %}; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in1 }} {% endif %};;
        {% if i + 1 < in1_d1 %}
    INC LR1 1 ;;
        {% endif %}
    {% endfor %}
plane:
    SET LR1 CR0 ; LD.MULT R0 LR1 {{ cr.s0 }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    {% for c in range(in1_d1) %}
        {% for i in range(chunks) %}
    {{ product(cr.ds_pair ~ '.L' if i == chunks - 1 else 'CR15.L', i < chunks - 1) }} {% if i == chunks - 1 and c + 1 < in1_d1 %}; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.s0 }} {% endif %};;
        {% endfor %}
        {% if c + 1 < in1_d1 %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
        {% endif %}
    {% endfor %}
{% else %}
    DEC LR4 1 ;;
reciprocal:
    LD.MULT R0 LR1 {{ cr.in1 }} ;;
    {{ inverse('LR1') }} ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.in1_d1 }} reciprocal ;;

plane:
    SET LR1 CR0 ;;
column:
    LD.MULT R0 LR1 {{ cr.s0 }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
{% if chunks <= 32 %}
    {% for i in range(chunks) %}
    {{ product(cr.ds_pair ~ '.L' if i == chunks - 1 else 'CR15.L', i < chunks - 1) }} ;;
    {% endfor %}
{% else %}
    SET LR3 LR2 ;;
    INC LR3 {{ chunks - 2 }} ;;
chunk:
    {{ product('CR15.L', true) }} ; BLT.S LR2 LR3 chunk ;;
    {{ product(cr.ds_pair ~ '.L') }} ;;
{% endif %}
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.in1_d1 }} column ;;
{% endif %}
    BLT.S LR2 {{ cr.rows }} plane ;;
    HALT ;;
