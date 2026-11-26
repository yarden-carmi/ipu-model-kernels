{% set tiles = (n + 127) // 128 %}
{% set tail = (n - 1) % 128 + 1 %}
{% set chunks = (k + 127) // 128 %}
{% set dots = chunks <= 2 and chunks * tail < k %}
{% set full = cr.full ~ '.L' %}
{% set q = cr.qf_in0 ~ '.L' %}
{% macro fetch() %}INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.coeff }} LR0{% endmacro %}
{% macro store(ds) %}INC LR4 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4{% endmacro %}
{% macro mac() %}MULT.RC.VE LR0 LR7 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% endmacro %}
{% macro taps(label, count, finish) %}
{% if count > 1 %}
{{ label }}:
    {{ mac() }} ; INC LR7 1 ; {{ fetch() }} ; BLT.S LR7 LR8 {{ label }} ;;
{% endif %}
    {{ mac() }} ; INC LR7 1 {{ finish }} ;;
{% endmacro %}
{% macro scalar(label, ds, finish) %}
{% if chunks <= 2 %}
    {{ fetch() }} ; SET LR7 LR14 ; SET LR8 {{ cr.first_bound }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; {{ fetch() }} ;;
{% if chunks == 2 %}
    {{ taps(label ~ '_first', 128, ' ; ' ~ fetch()) }}
    SET LR7 LR15 ; SET LR8 {{ cr.last_bound }} ;;
{% endif %}
    {{ taps(label ~ '_last', (k - 1) % 128 + 1, ' ; ' ~ store(ds) ~ finish) }}
{% else %}
    {{ fetch() }} ; SET LR10 LR2 ; SET LR9 {{ cr.chunks }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{{ label }}_chunk:
    INC LR10 1 ; LD.MULT R0 LR10 {{ cr.in0 }} ; SET LR7 LR14 ; SET LR8 {{ cr.first_bound }} ;;
    DEC LR9 1 ; {{ fetch() }} ; BEQ LR9 CR1 {{ label }}_partial ;;
    {{ taps(label ~ '_whole', 128, ' ; B ' ~ label ~ '_chunk') }}
{{ label }}_partial:
    SET LR8 {{ cr.last_bound }} ;;
    {{ taps(label ~ '_last', (k - 1) % 128 + 1, ' ; ' ~ store(ds) ~ finish) }}
{% endif %}
{% endmacro %}
{% macro dot_pair(more, finish) %}
{% for j in range(chunks) %}
    MULT.RC.VV LR{{ j }} R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR11 {{ (cr.partial if j == chunks - 1 else cr.full) }}.L
    {% if j == 0 %}; INC LR11 1{% endif %}
    {% if more or j < chunks - 1 %}; INC LR3 1 ; LD.MULT R0 LR3 {{ cr.coeff }}{% endif %}
    {% if j == chunks - 1 %}{{ finish }}{% endif %} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR13 CR0 ; SET LR5 {{ cr.m }} ;;
    INC LR1 128 ; DEC LR14 1 ; INC LR15 127 ;;
    DEC LR2 1 ; DEC LR4 1 ;;
{% for i in range(5) %}
    {% if i %}INC LR13 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR13 ;;
{% endfor %}
{% if dots and tail > 1 %}
{% set bound = tail - 2 - (1 if chunks == 1 else 0) %}
    SET LR12 CR0 ;;
{% if bound != 0 %}
    {{ 'INC' if bound > 0 else 'DEC' }} LR12 {{ bound if bound > 0 else -bound }} ;;
{% endif %}
{% endif %}
token:
    SET LR3 LR14 ; SET LR6 {{ cr.tiles }} ;;
{% if chunks <= 2 and (tiles > 1 or not dots) %}
    INC LR2 1 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% if chunks == 2 %}
    INC LR2 1 ; LD.MULT R1 LR2 {{ cr.in0 }} ;;
{% endif %}
{% endif %}
{% if tiles > 1 %}
    DEC LR6 1 ;;
wide:
    {{ scalar('wide', cr.full, ' ; DEC LR6 1 ; BNE LR6 CR1 wide') }}
{% endif %}
{% if dots %}
{% if tiles > 1 %}    DEC LR2 {{ chunks }} ;;{% endif %}
{% for j in range(chunks) %}
    INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR{{ j }} ;;
{% endfor %}
    INC LR3 1 ; LD.MULT R1 LR3 {{ cr.coeff }} ; SET LR11 LR14 ;;
    MULT.VE LR1 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; INC LR3 1 ; LD.MULT R0 LR3 {{ cr.coeff }} ;;
{% if tail > 1 %}
dot_tail:
    {{ dot_pair(true, ' ; BLT.S LR11 LR12 dot_tail') }}
{% endif %}
    {{ dot_pair(false, ' ; ' ~ store(cr.tail) ~ ' ; DEC LR5 1 ; BNE LR5 CR1 token') }}
{% else %}
    {{ scalar('narrow', cr.tail, ' ; DEC LR5 1 ; BNE LR5 CR1 token' if chunks <= 2 else '') }}
{% if chunks > 2 %}
    SET LR2 LR10 ; DEC LR5 1 ; BNE LR5 CR1 token ;;
{% endif %}
{% endif %}
    HALT ;;
