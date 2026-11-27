{% set full = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro offset(reg, value) %}
{% for n in range(0, value | abs, 255) %}
    {{ 'INC' if value > 0 else 'DEC' }} {{ reg }} {{ [255, (value | abs) - n] | min }} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR12 CR0 ; SET LR13 CR0 ;;
row:
    SET LR3 CR0 ;;
col:
    SET LR5 CR0 ; SET LR14 CR0 ;;
    INC LR14 128 ;;
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ; MULT.RC.VE LR14 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ; MULT.RC.VE LR14 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
{% for y in range(kh) %}
{% for x in range(kw) %}
    SET LR8 LR2 ; SET LR9 LR3 ;;
    {{ offset('LR8', y - padding) }}
    {{ offset('LR9', x - padding) }}
    BLT.S LR8 CR0 skip_{{y}}_{{x}} ;;
    BGE.S LR8 {{ cr.height }} skip_{{y}}_{{x}} ;;
    BLT.S LR9 CR0 skip_{{y}}_{{x}} ;;
    BGE.S LR9 {{ cr.width }} skip_{{y}}_{{x}} ;;
    SET LR7 CR0 ; SET LR9 LR12 ; ADD LR8 LR3 LR13 ;;
    {{ offset('LR8', x - padding) }}
{% if y == 0 %}
    BNE LR13 CR0 odd_{{y}}_{{x}} ;;
    DEC LR9 1 ; {{ offset('LR8', in0_d3) }}
    B addressed_{{y}}_{{x}} ;;
odd_{{y}}_{{x}}:
    {{ offset('LR8', -in0_d3) }}
addressed_{{y}}_{{x}}:
{% elif y == 2 %}
    BEQ LR13 CR0 even_{{y}}_{{x}} ;;
    INC LR9 1 ; {{ offset('LR8', -in0_d3) }}
    B addressed_{{y}}_{{x}} ;;
even_{{y}}_{{x}}:
    {{ offset('LR8', in0_d3) }}
addressed_{{y}}_{{x}}:
{% endif %}
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
ic_{{y}}_{{x}}:
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    MULT.RC.VE LR14 LR8 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    MULT.RC.VE LR14 LR8 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR5 1 ; INC LR7 1 ;;
    BGE.S LR7 {{ cr.channels }} end_{{y}}_{{x}} ;;
    {{ offset('LR9', in0_d2 // 2) }}
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    B ic_{{y}}_{{x}} ;;
    B end_{{y}}_{{x}} ;;
skip_{{y}}_{{x}}:
    {{ offset('LR5', 2 * cin) }}
end_{{y}}_{{x}}:
{% endfor %}
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.width }} col ;;
    INC LR2 1 ; BEQ LR13 CR0 row_even ;;
    SET LR13 CR0 ; INC LR12 1 ; B row_next ;;
row_even:
    {{ offset('LR13', in0_d3) }}
row_next:
    BLT.S LR2 {{ cr.height }} row ;;
    HALT ;;
