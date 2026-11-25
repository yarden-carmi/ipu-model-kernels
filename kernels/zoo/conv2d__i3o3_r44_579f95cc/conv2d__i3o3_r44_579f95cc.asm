{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set width = cr.width ~ '.L' %}

{% macro imm(reg, n) %}
    SET {{ reg }} CR0 ;;
{% for i in range(0, n, 255) %}
    INC {{ reg }} {{ [255, n-i] | min }} ;;
{% endfor %}
{% endmacro %}

{% macro gather(ky, kx) %}
{% set tag = ky ~ '_' ~ kx %}
{% if stride == 1 %}
    {{ imm('LR4', kx) }}
    LD.MULT R0 LR4 {{ cr.masks }} ;;
    {{ imm('LR4', 127+kx) }}
    MULT.RC.VV LR4 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
{% else %}
    MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
    {{ imm('LR4', 255) }}
    {{ imm('LR5', kx) }}
    DEC LR5 1 ;;
    {{ imm('LR6', out0_d3) }}
    {{ imm('LR7', in0_d3) }}
x_{{ tag }}:
    BLT.S LR5 CR0 advance_{{ tag }} ;;
    BGE.S LR5 LR7 advance_{{ tag }} ;;
    MULT.RC.VE LR4 LR5 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
advance_{{ tag }}:
    INC LR5 2 ; DEC LR4 1 ; DEC LR6 1 ;;
    BLT.S CR0 LR6 x_{{ tag }} ;;
{% endif %}
    ACTIVATE.QUANTIZE identity {{ width }} {{ qi }} {{ cr.patches }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

{% macro vertical(ky) %}
    SET LR2 LR15 ; SET LR3 CR0 ;;
{% if ky != 1 %}
    {{ 'SUB' if ky == 0 else 'ADD' }} LR2 LR2 {{ cr.in0_d1 }} ;;
{% endif %}
channel_{{ ky }}:
{% if ky == 0 %}
    BLT.S LR2 CR0 zero_{{ ky }} ;;
{% elif ky == 2 %}
    BGE.S LR2 {{ cr.input_rows }} zero_{{ ky }} ;;
{% endif %}
{% if stride == 1 %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR13 ;;
{% else %}
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% endif %}
{% for kx in range(3) %}{{ gather(ky, kx) }}{% endfor %}
    INC LR2 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.in0_d1 }} channel_{{ ky }} ;;
{% if ky != 1 %}
    BEQ LR0 CR0 end_{{ ky }} ;;
zero_{{ ky }}:
    MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
zero_loop_{{ ky }}:
{% for kx in range(3) %}
    ACTIVATE.QUANTIZE identity {{ width }} {{ qi }} {{ cr.patches }} LR1 ;;
    INC LR1 1 ;;
{% endfor %}
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.in0_d1 }} zero_loop_{{ ky }} ;;
end_{{ ky }}:
{% endif %}
{% endmacro %}

{% macro pair() %}
    MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;;
    MULT.RC.VE LR13 LR12 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR12 1 ;;
{% endmacro %}

{% macro panel(count, tag) %}
    LD.MULT R0 LR5 {{ cr.weights }} ; SET LR7 CR0 ; SET LR12 LR13 ;;
    LD.MULT R1 LR5 {{ cr.weights }} ; INC LR5 1 ; DEC LR7 1 ; DEC LR12 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; INC LR5 1 ;;
{% if count > 1 %}
mac_{{ tag }}:
    MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;;
    MULT.RC.VE LR13 LR12 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR12 1 ; LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; BLT.S LR7 {{ 'LR8' if count == 128 else 'LR9' }} mac_{{ tag }} ;;
{% endif %}
    {{ pair() }}
{% endmacro %}

    SET LR0 CR0 ; SET LR10 CR0 ; SET LR15 CR0 ;;
    {{ imm('LR13', 128) }}
    {{ imm('LR8', 126) }}
    {{ imm('LR9', [0, taps % 128 - 2] | max) }}
    {{ imm('LR14', panels) }}
row:
{% if stride == 2 %}
    LD.MULT.CYCLIC LR0 {{ cr.masks }} LR13 ;;
{% endif %}
    SET LR1 CR0 ;;
{% for ky in range(3) %}{{ vertical(ky) }}{% endfor %}
    SET LR5 CR0 ;;
filter:
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR0 ; SET LR4 CR0 ; SET LR11 CR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR5 1 ;;
{% if panels %}
full_panel:
    {{ panel(128, 'full') }}
    INC LR11 1 ;;
    BLT.S LR11 LR14 full_panel ;;
{% endif %}
{% if taps % 128 %}{{ panel(taps % 128, 'tail') }}{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ width }} {{ qo }} {{ cr.out0 }} LR10 ;;
    INC LR10 1 ;;
    BLT.S LR5 {{ cr.weight_rows }} filter ;;
    ADD LR15 LR15 {{ cr.step }} ;;
    BLT.S LR10 {{ cr.output_rows }} row ;;
    HALT ;;
