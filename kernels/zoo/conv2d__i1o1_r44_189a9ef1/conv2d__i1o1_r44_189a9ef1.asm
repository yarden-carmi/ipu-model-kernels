{% if fork %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set step = 32 if cin % 32 == 0 else (8 if cin % 8 == 0 else 1) %}
{% macro fork_channel(i, tag) %}
    {% set cur = 'LR15' if i % 2 == 0 else 'LR12' %}
    {% set nxt = 'LR12' if i % 2 == 0 else 'LR15' %}
    MULT.RC.VE {{ cur }} LR11 0 LR15 {{ full }} {{ qi }} ; ACC.ADD ; INC LR11 1 ; INC LR7 1 {% if i + 1 < step %}; LD.MULT.CYCLIC LR7 {{ cr.weights }} {{ nxt }}{% else %}; BLT.S LR11 {{ cr.full }}.H channels_{{ tag }}{% endif %} ;;
{% endmacro %}
{% macro sweep(tag) %}
    SET LR11 CR0 ;;
    DEC LR11 1 ;;
channels_{{ tag }}:
    LD.MULT.CYCLIC LR7 {{ cr.weights }} LR15 ;;
    {% for i in range(step) %}{{ fork_channel(i, tag) }}{% endfor %}
{% endmacro %}
{% macro bias_digit(slot, acc) %}
    LD.MULT.CYCLIC LR7 {{ cr.weights }} {{ slot }} ;;
    MULT.RC.VE {{ slot }} CR1 0 LR15 {{ full }} {{ qi }} ; {{ acc }} ; INC LR7 1 ;;
{% endmacro %}
    INC LR12 128 ;;
    {% for p in range(padding) %} SUB LR1 LR1 {{ cr.input_hw }}.H ;; {% endfor %}
    DEC LR1 {{ padding }} ;;
batch:
    SET LR2 LR1 ; SET LR4 CR0 ;;
    DEC LR4 {{ padding }} ;;
line:
    SET LR3 LR2 ; SET LR5 CR0 ;;
    DEC LR5 {{ padding }} ;;
pixel:
    SET LR7 CR0 ; SET LR8 LR3 ; SET LR10 LR4 ;;
    {{ bias_digit('LR15', 'ACC.ADD.FIRST') }}
    {{ bias_digit('LR15', 'ACC.ADD') }}
    SET LR13 LR4 ; SET LR14 LR5 ;;
    INC LR13 {{ kh }} ; INC LR14 {{ kw }} ;;
ky:
    BLT.S LR10 CR0 skip_line ;;
    BGE.S LR10 {{ cr.input_hw }}.L skip_line ;;
    SET LR9 LR5 ; SET LR0 LR8 ;;
kx:
    BLT.S LR9 CR0 skip_tap ;;
    BGE.S LR9 {{ cr.input_hw }}.H skip_tap ;;
    LD.MULT R0 LR0 {{ cr.in0 }} ;;
    {% for pass in range(2) %}{{ sweep(pass) }}{% endfor %}
    B next_tap ;;
skip_tap:
    ADD LR7 LR7 {{ cr.tail }}.L ;;
next_tap:
    INC LR9 1 ; INC LR0 1 ;;
    BLT.S LR9 LR14 kx ;;
    B next_line ;;
skip_line:
    ADD LR7 LR7 {{ cr.tail }}.H ;;
next_line:
    INC LR10 1 ; ADD LR8 LR8 {{ cr.input_hw }}.H ;;
    BLT.S LR10 LR13 ky ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.row_delta }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; INC LR3 {{ stride }} ;;
    INC LR6 1 ; INC LR5 {{ stride }} ;;
    BLT.S LR5 {{ cr.yend }} pixel ;;
    ADD LR2 LR2 {{ cr.blocks }} ; INC LR4 {{ stride }} ;;
    BLT.S LR4 {{ cr.xend }} line ;;
    ADD LR1 LR1 {{ cr.kernel_last }} ; BLT.S LR6 {{ cr.panel_tail }} batch ;;
    HALT ;;
{% else %}
{% macro shift(r,n) %}
{% for tile in range(0,n|abs,8160) %}
{% for k in range(tile,[tile+8160,n|abs]|min,255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255,(n|abs)-k]|min }} ;;
{% endfor %}
{% endfor %}
{% endmacro %}

{% macro channel(i) %}
{% set cur = 'LR15' if i % 2 == 0 else 'LR12' %}
{% set nxt = 'LR12' if i % 2 == 0 else 'LR15' %}
 MULT.RC.VE {{ cur }} LR11 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 ; INC LR11 1 {% if i < 15 %}; LD.MULT.CYCLIC LR4 {{ cr.weights }} {{ nxt }}{% else %}; BNE LR10 CR0 channels{% endif %} ;;
{% endmacro %}

{% macro store(mask) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
{% endmacro %}

{% if dot %}
 {{ shift('LR12', cout - 3) }}
{% endif %}
 {{ shift('LR0', -padding) }}
 {{ shift('LR1', -padding * (in0_d3 + 1)) }}
 oy:
 SET LR2 CR0 ;;
 {{ shift('LR2', -padding) }}
 ox:
 SET LR3 CR0 ; SET LR4 CR0 ;;
 block:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 MULT.RC.VE LR15 {{ 'CR1' if bias else 'CR0' }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR5 CR0 ; SET LR14 LR1 ; INC LR4 1 ;;
 ky:
 ADD LR7 LR0 LR5 ; SET LR6 CR0 ;;
 BLT.S LR7 CR0 skip_row ;;
 BGE.S LR7 {{ cr.input_hw }}.L skip_row ;;
 kx:
 ADD LR8 LR2 LR6 ;;
 BLT.S LR8 CR0 skip ;;
 BGE.S LR8 {{ cr.input_hw }}.H skip ;;
 ADD LR9 LR14 LR6 ;;
{% if chunks > 1 %}
 SET LR7 LR9 ;;
 {% for i in range(chunks - 1) %} ADD LR9 LR9 LR7 ;; {% endfor %}
{% endif %}
 SET LR7 CR0 ;;
 INC LR7 {{ chunks }} ;;
 chunk:
{% if dot %}
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR15 ;;
 LD.MULT R0 LR4 {{ cr.weights }} ; SET LR11 {{ cr.full }}.H ;;
 {% if cout > 1 %}
 dot_lane:
 MULT.RC.VV LR15 R0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.full }}.L ; INC LR11 1 ; LD.MULT R0 LR4 {{ cr.weights }} ; INC LR4 1 ; BLT.S LR11 LR12 dot_lane ;;
 {% endif %}
 MULT.RC.VV LR15 R0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.full }}.L ; INC LR4 1 ; INC LR11 1 ;;
{% else %}
 SET LR10 {{ cr.panel_tail }}.H ; BEQ LR7 CR1 chunk_load ;;
 SET LR10 CR0 ;;
 INC LR10 128 ;;
 chunk_load:
 LD.MULT R0 LR9 {{ cr.in0 }} ; SET LR11 {{ cr.full }}.H ;;
 channels:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; DEC LR10 16 ;;
 {% for i in range(16) %}{{ channel(i) }}{% endfor %}
{% endif %}
 DEC LR7 1 ; INC LR9 1 ; BNE LR7 CR1 chunk ;;
 B next ;;
 skip:
 ADD LR4 LR4 {{ cr.panel_tail }}.L ;;
 next:
 INC LR6 1 ; BLT.S LR6 {{ cr.kernel_last }}.L kx ;;
 B next_row ;;
 skip_row:
 {% for x in range(kw) %} ADD LR4 LR4 {{ cr.panel_tail }}.L ;; {% endfor %}
 next_row:
 INC LR5 1 ; ADD LR14 LR14 {{ cr.input_hw }}.H ; BLT.S LR5 {{ cr.kernel_last }}.H ky ;;
 INC LR3 1 ;;
 BLT.S LR3 {{ cr.blocks }} fullstore ;;
 {{ store(cr.tail ~ '.L') }}
 INC LR13 1 ; B advance ;;
 fullstore:
 {{ store(cr.full ~ '.L') }}
 INC LR13 1 ; B block ;;
 advance:
 INC LR1 {{ stride }} ; INC LR2 {{ stride }} ;;
 BLT.S LR2 {{ cr.xend }} ox ;;
 ADD LR1 LR1 {{ cr.row_delta }} ; INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.yend }} oy ;;
 HALT ;;
{% endif %}
