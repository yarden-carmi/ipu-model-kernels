{% set full = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% macro offset(reg, n) %}
{% for i in range(0, n | abs, 255) %}
    {{ 'INC' if n > 0 else 'DEC' }} {{ reg }} {{ [255, (n | abs) - i] | min }} ;;
{% endfor %}
{% endmacro %}
{% macro init(reg, n) %}
    SET {{ reg }} CR0 ;;
    {{ offset(reg, n) }}
{% endmacro %}
{% macro coefficient(mult, first=false) %}
{% for digit in range(3) %}
    LD.MULT R0 LR6 {{ cr.weights }} ;;
    {{ mult }} 0 LR15 {{ full }} {{ qi }} ; ACC.ADD{{ '.FIRST' if first and loop.first else '' }} ; INC LR6 1 ;;
{% endfor %}
{% endmacro %}

{% if stride == 2 %}
{# Rearrange an entire input row, preserving its quantization scale. #}
    SET LR15 CR0 ; SET LR6 CR0 ; SET LR7 {{ cr.in0_d2 }} ;;
prep_y:
    SET LR8 {{ cr.cin }} ;;
prep_row:
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR15 ;;
{% macro parity(p) %}
    SET LR0 {{ cr.src_lo }} ; SET LR1 {{ cr.src_hi }} ;;
    SET LR2 {{ cr.dst_lo }} ; SET LR3 {{ cr.dst_hi }} ;;
    {{ init('LR9', 8) }}
{% if p %}
    ADDBI LRD0 1 ;;
    ADDBI LRD2 64 ;;
{% endif %}
prep_parity_{{ p }}:
    MULT.RC.VE LR15 CR1 0 LR15 {{ full }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
    ADDBI LRD0 16 ; DEC LR9 1 ;;
    ADDBI LRD2 8 ;;
    BLT.S LR15 LR9 prep_parity_{{ p }} ;;
{% endmacro %}
    {{ parity(0) }}
    {{ parity(1) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.rows }} LR6 ;;
    INC LR6 1 ; DEC LR8 1 ;;
    BLT.S LR15 LR8 prep_row ;;
    DEC LR7 1 ;;
    BLT.S LR15 LR7 prep_y ;;
{% endif %}

    SET LR15 CR0 ; SET LR2 CR0 ; SET LR7 CR0 ;;
    {{ init('LR6', 1) }}
    {{ init('LR8', groups) }}
    LD.MULT.CYCLIC LR15 {{ cr.weights }} LR15 ;;
    {{ init('LR14', 256) }}
    LD.MULT.CYCLIC LR15 {{ cr.weights }} LR14 ;;
    INC LR14 128 ;;
    LD.MULT.CYCLIC LR15 {{ cr.weights }} LR14 ;;
group:
    {{ init('LR9', cout // groups) }}
channel:
    SET LR1 LR2 ;;
    {{ init('LR0', -padding) }}
    {{ offset('LR1', -padding * cin) }}
    {{ init('LR4', out0_d3) }}
block:
    {{ init('LR5', 128) }}
    {{ coefficient('MULT.VE LR15 CR1', true) }}
segment:
    SET LR10 {{ cr.group_in }} ; SET LR11 LR1 ;;
input_channel:
    SET LR12 LR0 ; SET LR13 LR11 ;;
    INC LR12 {{ kh - 1 }} ;;
{% for k in range(kh-1) %}
    ADD LR13 LR13 {{ cr.cin }} ;;
{% endfor %}
ky:
    {{ init('LR14', 128) }}
    BLT.S LR12 LR15 fallback ;;
    BGE.S LR12 {{ cr.in0_d2 }} fallback ;;
    LD.MULT.CYCLIC LR13 {{ cr.rows if stride == 2 else cr.in0 }} LR14 ;;
    B tap ;;
fallback:
    LD.MULT.CYCLIC LR2 {{ cr.rows if stride == 2 else cr.in0 }} LR14 ;;
tap:
{% set offsets = namespace(previous=0) %}
{% for kx in range(kw) %}
{% set dx = kx - padding %}
{% set xoff = out0_d3 + dx // stride + 64 * (dx % stride) %}
{% if loop.first %}
    SUB LR14 LR5 LR4 ;;
{% endif %}
    {{ offset('LR14', xoff - offsets.previous) }}
    {{ coefficient('MULT.RC.VV LR14 R0') }}
{% set offsets.previous = xoff %}
{% endfor %}
    DEC LR12 1 ; SUB LR13 LR13 {{ cr.cin }} ;;
    BGE.S LR12 LR0 ky ;;
    INC LR11 1 ; DEC LR10 1 ;;
    BLT.S LR15 LR10 input_channel ;;

    BLT.S LR5 LR4 split_row ;;
    SUB LR5 LR5 LR4 ; INC LR0 {{ stride }} ;;
{% for s in range(stride) %}
    ADD LR1 LR1 {{ cr.cin }} ;;
{% endfor %}
    {{ init('LR14', out0_d2 * stride - padding) }}
    BGE.S LR0 LR14 last_block ;;
    {{ init('LR4', out0_d3) }}
    BNE LR5 LR15 segment ;;
    B full_block ;;
split_row:
    SUB LR4 LR4 LR5 ;;
full_block:
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ full }} {{ qo }} {{ cr.out0 }} LR7 ;;
    INC LR7 1 ;;
    B block ;;
last_block:
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full }}.H {{ qo }} {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; DEC LR9 1 ;;
    BLT.S LR15 LR9 channel ;;
    ADD LR2 LR2 {{ cr.group_in }} ; DEC LR8 1 ;;
    BLT.S LR15 LR8 group ;;
    HALT ;;
