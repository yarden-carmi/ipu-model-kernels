{% set triple = m > 1 %}
{% set full_chunks = (k - 1) // 127 %}
{% set tail = k - full_chunks * 127 %}
{% set ds = cr.full_ds ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro tap(last=false, loop_label='', split=true) %}
    INC LR6 1 ; MULT.RC.VE LR0 LR6 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD
    {% if split %};;
    ADD LR7 LR6 {{ cr.scalar_bank }} ; MULT.RC.VE LR0 LR7 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD
    {% endif %}
    ; ADD LR5 LR5 {{ cr.plane }}
    {% if not last %}; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0{% endif %}
    {% if loop_label %}; BNE LR6 LR13 {{ loop_label }}{% endif %} ;;
{% endmacro %}
{% macro load_coeff(reg) %}
    SET LR12 LR4 ; INC LR4 1 ; LD.MULT {{ reg }} LR12 {{ cr.coeff }} ;;
{% endmacro %}
{% macro taps(count, label, split) %}
    SET LR6 CR0 ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
    {% set groups = (count - 1) // 8 %}
    {% if groups > 1 %}
    SET LR13 CR0 ;;
    INC LR13 {{ groups * 8 - (0 if split else 1) }} ;;
{{ label }}:
    {% for i in range(8) %}
    {{ tap(false, label if loop.last else '', split) }}
    {% endfor %}
    {% endif %}
    {% for i in range(count - (groups * 8 if groups > 1 else 0)) %}
    {{ tap(loop.last, '', split) }}
    {% endfor %}
{% endmacro %}
{% macro chunk(count, label) %}
    {{ load_coeff('R0') }}
    {{ load_coeff('R1') }}
    {% if triple %}SET LR14 LR5 ;;{% endif %}
    {{ taps(count, label, true) }}
    {% if triple %}
    SET LR5 LR14 ;;
    {{ load_coeff('R0') }}
    {{ taps(count, label ~ '_fine', false) }}
    {% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR1 ;{% if not loop.first %} INC LR1 1 ;{% endif %} ;;
{% endfor %}
    SET LR1 CR0 ;;
batch:
    SET LR3 CR0 ;;
channel:
    SET LR9 LR2 ; SET LR10 CR0 ; SET LR11 CR0 ;;
tile:
    LD.MULT R0 LR3 {{ cr.coeff }} ; SET LR4 LR3 ; SET LR5 LR9 ;;
    INC LR4 1 ; SET LR7 {{ cr.scalar_bank }} ; LD.MULT R1 LR4 {{ cr.coeff }} ; MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
{% if triple %}
    INC LR4 1 ; LD.MULT R0 LR4 {{ cr.coeff }} ; MULT.EE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
    MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; SET LR4 LR3 ;;
{% else %}
    MULT.EE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; SET LR4 LR3 ;;
{% endif %}
{% if full_chunks %}
    SET LR8 CR0 ;;
    INC LR8 {{ full_chunks - 1 }} ;;
full_chunk:
    {{ chunk(127, 'full_taps') }}
    DEC LR8 1 ; BNE LR8 CR0 full_chunk ;;
{% endif %}
    {{ chunk(tail, 'tail_taps') }}
{% if out0_d3 > 128 and out0_d3 % 128 %}
    INC LR11 1 ;;
    BNE LR11 {{ cr.width_tiles }} full_store ;;
{% endif %}
{% macro store(dsreg) %}
    ACTIVATE.QUANTIZE generic {{ dsreg }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    {{ store(cr.tail_ds) }}
    SET LR11 CR0 ;;
advance:
    INC LR1 1 ; INC LR9 1 ; INC LR10 1 ;;
    BNE LR10 {{ cr.plane }} tile ;;
    ADD LR3 LR3 {{ cr.coeff_stride }} ;;
    BNE LR3 {{ cr.coeff_end }} channel ;;
    ADD LR2 LR2 {{ cr.batch_stride }} ; DEC LR15 1 ;;
    BNE LR15 CR0 batch ;;
    HALT ;;
{% if out0_d3 > 128 and out0_d3 % 128 %}
full_store:
    {{ store(cr.full_ds) }}
    B advance ;;
{% endif %}
