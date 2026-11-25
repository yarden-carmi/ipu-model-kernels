{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set pack = 2 if out0_d3 <= 64 and out0_d2 % 2 == 0 else 1 %}
{% set chunks = (in0_d3 + 127) // 128 %}
{% macro set_imm(reg, value) %}
    SET {{ reg }} CR0 ;;
{% for i in range(0, value, 255) %}
    INC {{ reg }} {{ [255, value-i] | min }} ;;
{% endfor %}
{% endmacro %}

{# Stage one zero-extended, stride-adjusted vector per input row and x tap. #}
{% macro halo(label) %}
{% if padding %}
    {{ set_imm('LR6', padding * kw * chunks) }}
    MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
{{ label }}:
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.windows }} LR7 ; DEC LR6 1 ;;
    INC LR7 1 ; BNE LR6 CR0 {{ label }} ;;
{% endif %}
{% endmacro %}

    {{ set_imm('LR4', 128) }}
    SET LR5 CR0 ; SET LR14 CR0 ;;
    DEC LR5 1 ;;
batch:
    LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ; SET LR7 CR1 ;;
    {{ set_imm('LR3', 256) }}
    {{ set_imm('LR2', 384) }}
    LD.MULT.CYCLIC LR0 {{ cr.weights }} LR2 ;;
{% if chunks == 1 %}
    LD.MULT.CYCLIC LR0 {{ cr.weights }} LR3 ;;
{% endif %}
    {{ set_imm('LR9', in0_d1) }}
stage_channel:
    {{ halo('top') }}
    {{ set_imm('LR8', in0_d2) }}
stage_y:
{% macro stage_part(c) %}
{% set slot = 'LR4' if c == 0 else 'LR3' %}
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} {{ slot }} ; INC LR5 1 ; SET LR10 LR4 ;;
{% if c == chunks - 1 and in0_d3 % 128 %}
    MULT.RC.VE {{ slot }} CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.in_tail }}.L {{ qi }} {{ cr.windows }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.windows }} {{ slot }} ;;
{% endif %}
{% if chunks == 2 %}
    LD.MULT.CYCLIC LR0 {{ cr.weights }} {{ 'LR3' if c == 0 else 'LR4' }} ;;
{% endif %}
    DEC LR10 {{ padding + 1 }} ;;
{% if stride == 2 %}
    SET LR11 LR10 ; SET LR2 CR1 ;;
    INC LR11 128 ; INC LR2 1 ;;
{% endif %}
    {{ set_imm('LR6', kw) }}
stage_x_{{ c }}:
{% if stride == 1 %}
    MULT.RC.VE LR10 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR10 1 ;;
{% else %}
    MULT.RC.VE LR10 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ; INC LR10 1 ;;
    MULT.RC.VE LR11 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR2 ; INC LR11 1 ;;
{% endif %}
    ACTIVATE.QUANTIZE identity {{ cr.width }}.L {{ qi }} {{ cr.windows }} LR7 ; DEC LR6 1 ;;
    INC LR7 1 ; BNE LR6 CR0 stage_x_{{ c }} ;;
{% endmacro %}
{% for c in range(chunks) %}{{ stage_part(c) }}{% endfor %}
    DEC LR8 1 ;;
    BNE LR8 CR0 stage_y ;;
    {{ halo('bottom') }}
    DEC LR9 1 ;;
    BNE LR9 CR0 stage_channel ;;
    SET LR1 {{ cr.group_plane }} ; SET LR6 CR1 ;;
    ADD LR1 LR1 {{ cr.next_plane }} ;;
    INC LR1 {{ 1 + kh * kw * chunks }} ;;

{# A shifted cyclic read places the second row in the packed output lanes.
   The preceding slot and the staged vector's unused lanes are zero. #}
{% macro taps(high) %}
{% for c in range(chunks) %}
    LD.MULT.CYCLIC LR11 {{ cr.windows }} LR4 ; INC LR11 1{% if c %} ; DEC LR3 {{ kw }}{% if high %} ; DEC LR2 {{ kw }}{% endif %}{% endif %} ;;
{% for x in range(kw) %}
{% if high %}
    MULT.RC.VE LR10 LR2 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR2 1 ;;
{% endif %}
    MULT.RC.VE LR10 LR3 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR3 1{% if x + 1 < kw %} ; LD.MULT.CYCLIC LR11 {{ cr.windows }} LR4 ; INC LR11 1{% endif %} ;;
{% endfor %}
{% endfor %}
{% endmacro %}

group:
    {{ set_imm('LR13', cout // groups) }}
channel:
    SET LR7 LR1 ;;
    {{ set_imm('LR8', out0_d2 // pack) }}
{% macro add_bias() %}
{% if bias %}
    LD.MULT R0 LR6 {{ cr.weights }} ; SET LR12 LR6 ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT R1 LR12 {{ cr.weights }} ; INC LR12 1 ;;
    MULT.EE LR4 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT R1 LR12 {{ cr.weights }} ; INC LR12 1 ;;
    MULT.EE LR4 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
{% endif %}
{% endmacro %}
tile:
    MULT.EE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
    SET LR9 LR13 ; SET LR10 LR4 ; SET LR11 LR7 ;;
{% macro members(label) %}
    SET LR12 LR6 ;;
    DEC LR12 1 ; DEC LR11 1 ;;
    {{ set_imm('LR13', cin // groups) }}
ic_{{ label }}:
    LD.MULT R0 LR12 {{ cr.weights }} ; INC LR12 1 ; SET LR2 CR0 ;;
ky_{{ label }}:
{% if chunks == 2 %}
    INC LR12 1 ; SET LR3 LR2 ;;
    INC LR3 128 ;;
{% for c in range(chunks) %}
    LD.MULT.CYCLIC LR11 {{ cr.windows }} LR4 ; INC LR11 1{% if c %} ; DEC LR2 {{ kw }} ; DEC LR3 {{ kw }}{% endif %} ;;
{% for x in range(kw) %}
    MULT.RC.VE LR10 LR2 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR2 1 ; LD.MULT R1 LR12 {{ cr.weights }} ;;
    MULT.RC.VE LR10 LR3 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR3 1 ; INC LR12 1 ; LD.MULT R1 LR12 {{ cr.weights }} ;;
    MULT.RC.VE LR10 LR3 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; DEC LR12 1{% if x + 1 < kw %} ; LD.MULT.CYCLIC LR11 {{ cr.windows }} LR4 ; INC LR11 1{% endif %} ;;
{% endfor %}
{% endfor %}
    DEC LR12 1 ; BLT.S LR2 {{ cr.tap_end }} ky_{{ label }} ;;
{% else %}
    LD.MULT R1 LR12 {{ cr.weights }} ; INC LR12 1 ; SET LR3 LR2 ;;
    INC LR3 128 ;;
    {{ taps(true) }}
    LD.MULT R1 LR12 {{ cr.weights }} ; INC LR12 1 ; DEC LR11 {{ kw * chunks }} ; DEC LR3 {{ kw }} ;;
    {{ taps(false) }}
    DEC LR12 2 ; BLT.S LR2 {{ cr.tap_end }} ky_{{ label }} ;;
{% endif %}
    INC LR12 2 ; ADD LR11 LR11 {{ cr.next_plane }} ; DEC LR13 1 ;;
    BNE LR13 CR0 ic_{{ label }} ;;
{% endmacro %}
    {{ members('first') }}
{% if pack == 2 %}
    SET LR11 LR7 ; DEC LR10 {{ out0_d3 }} ;;
    INC LR11 {{ stride * kw * chunks }} ;;
    {{ members('second') }}
{% endif %}
    SET LR11 LR12 ;;
    {{ add_bias() }}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR7 {{ pack * stride * kw * chunks }} ; DEC LR8 1 ;;
    INC LR14 1 ; SET LR13 LR9 ; BNE LR8 CR0 tile ;;
    ADD LR6 LR11 CR1 ; DEC LR13 1 ;;
    BNE LR13 CR0 channel ;;
    ADD LR1 LR1 {{ cr.group_plane }} ; BLT.S LR6 {{ cr.weight_rows }} group ;;
    DEC LR15 1 ;;
    BNE LR15 CR0 batch ;;
    HALT ;;
