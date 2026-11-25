{% set ds = cr.active ~ '.L' %}
{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set pack = in1_d3 if in0_d2 % in1_d3 == 0 else (in1_d3 // 2 if in1_d3 > 8 and in0_d2 % (in1_d3 // 2) == 0 else 8) %}
{% set parts = in1_d3 // pack %}
{% macro mac(idx, first=false) %}
    MULT.RC.VE LR0 {{ idx }} 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro next_coeff(dst, cyclic=false) %}
    INC LR7 1 ; LD.MULT{% if cyclic %}.CYCLIC LR7 {{ cr.coeff }} {{ dst }}{% else %} {{ dst }} LR7 {{ cr.coeff }}{% endif %}
{%- endmacro %}
{% macro pair(taps, advance=false, tag='') %}
    {{ next_coeff('R0') }} ; SET LR1 CR0 ; SET LR2 LR10 ;;
    {{ next_coeff('R1') }} ; DEC LR1 1 ; DEC LR2 1 ;;
{% if parts == 1 %}
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; INC LR2 1{% if advance or not loop.last %} ; ADD LR6 LR6 {{ cr.in1_d2 }} ; LD.MULT.CYCLIC LR6 {{ cr.stripes }} LR0{% endif %}{% if advance and loop.last %} ; DEC LR9 1 ; BNE LR9 CR1 full_block{% endif %} ;;
{% endfor %}
{% else %}
    SET LR15 CR0 ;;
    INC LR15 {{ taps }} ;;
tap_{{ tag }}:
{% for part in range(parts) %}
    LD.MULT.CYCLIC LR6 {{ cr.stripes }} LR0 ;;
    {{ mac('LR1') }}{% if loop.first %} ; INC LR1 1{% endif %} ;;
    {{ mac('LR2') }}{% if loop.first %} ; INC LR2 1{% endif %}{% if loop.last %} ; ADD LR6 LR6 LR4 ; DEC LR15 1 ; BNE LR15 CR1 tap_{{ tag }}{% else %} ; INC LR6 1{% endif %} ;;
{% endfor %}
{% if advance %}
    DEC LR9 1 ; BNE LR9 CR1 full_block ;;
{% endif %}
{% endif %}
{% endmacro %}
{% macro block(taps, advance=false) %}
    SET LR13 LR6 ;;
    {{ pair(taps, false, ('full' if advance else 'tail') ~ '_a') }}
    SET LR6 LR13{% if parts == 1 %} ; LD.MULT.CYCLIC LR13 {{ cr.stripes }} LR0{% endif %} ;;
    {{ pair(taps, advance, ('full' if advance else 'tail') ~ '_b') }}
{% endmacro %}

{% macro gather_part(part) %}
    LD.MULT R0 LR4 {{ cr.in0 }} ; SET LR9 LR0 ; SET LR13 LR1 ;;
{% if parts > 1 %}
    MULT.VE LR8 CR0 0 LR8 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
{% endif %}
{% for octet in range(pack // 8) %}
    MULT.VE LR8 CR1 0 LR8 {{ ds }} {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
    {% if not loop.last %}ADDBI LRD0 {{ 8 * in0_d0 }} ;{% endif %} ADDBI LRD2 8 ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.stripes }} LR5 ;;
    INC LR5 1 ; INC LR4 1 ;;
    SET LR0 LR9 ; SET LR1 LR13 ; BNE LR4 {{ cr.group_rows }} gather_next_{{ part }} ;;
    SET LR4 CR0 ; ADDBI LRD0 1 ;;
gather_next_{{ part }}:
{% endmacro %}

    # Gather each padding-free packed sub-stripe separately. Keeping its
    # scale separate avoids losing small values next to a large neighbor.
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
gather_row:
    SET LR2 LR14 ; SET LR3 LR15 ;;
{% for part in range(parts) %}{{ gather_part(part) }}{% endfor %}
    BLT.S LR5 {{ cr.scratch_rows }} gather_row ;;

    # The first half is the untouched branch of the concatenation.
    SET LR0 CR0 ; SET LR3 CR0 ;;
copy_row:
    LD.MULT R0 LR3 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.copy_rows }} copy_row ;;

    SET LR4 CR0 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
{% if parts > 1 %}
    SET LR4 CR0 ;;
{% for part in range(parts) %}
    ADD LR4 LR4 {{ cr.in1_d2 }} ;;
{% endfor %}
    DEC LR4 {{ parts - 1 }} ;;
{% endif %}
    SET LR5 CR0 ; SET LR14 LR3 ;;
stripe:
    SET LR3 LR14 ; SET LR8 LR12 ; SET LR7 CR0 ;;
    DEC LR7 1 ;;
channel:
    SET LR6 LR5 ; {{ next_coeff('LR0', true) }} ;;
    {{ mac('CR1', true) }} ; {{ next_coeff('LR0', true) }} ; SET LR9 LR11 ;;
{% for digit in range(2) %}
    {{ mac('CR1') }} ; {{ next_coeff('LR0', true) }} ;;
{% endfor %}
    {{ mac('CR1') }}{% if parts == 1 %} ; LD.MULT.CYCLIC LR6 {{ cr.stripes }} LR0{% endif %} ;;
{% if k > 16 %}
full_block:
    {{ block(16, true) }}
{% endif %}
    {{ block((k - 1) % 16 + 1) }}
    ACTIVATE.QUANTIZE {{ 'generic' if act_out0 in ['silu', 'hardsigmoid', 'hardswish'] else act_out0 }} {{ ds }} {{ qo }} {{ cr.out0 }} LR3 ;;
    ADD LR3 LR3 {{ cr.in1_d2 }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    INC LR5 {{ parts }} ; INC LR14 1 ;;
    SUB LR15 LR14 {{ cr.copy_rows }} ;;
    BLT.S LR15 {{ cr.in1_d2 }} stripe ;;
    HALT ;;
