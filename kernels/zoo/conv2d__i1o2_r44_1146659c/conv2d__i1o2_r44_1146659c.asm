{% macro step(reg, n) %}
{% for tile in range(0, n|abs, 8160) %}
{% for i in range(tile, [tile+8160, n|abs]|min, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ reg }} {{ [255, (n|abs)-i]|min }} ;;
{% endfor %}
{% endfor %}
{% endmacro %}

{# Compute channel vectors into raster-order scratch. #}
 INC LR12 128 ; DEC LR0 {{ padding }} ;;
 {{ step('LR1', origin) }}
oy:
 SET LR2 CR0 ;;
 DEC LR2 {{ padding }} ;;
ox:
 SET LR3 CR0 ; SET LR4 CR0 ;;
 INC LR3 {{ blocks }} ;;
block:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 MULT.RC.VE LR15 {{ 'CR1' if bias else 'CR0' }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR4 1 ; SET LR5 CR0 ; SET LR14 LR1 ;;
ky:
 SET LR6 CR0 ;;
kx:
 ADD LR7 LR0 LR5 ; ADD LR8 LR2 LR6 ;;
 BLT.S LR7 CR0 skip ;;
 BGE.S LR7 {{ cr.in0_d2 }} skip ;;
 BLT.S LR8 CR0 skip ;;
 BGE.S LR8 {{ cr.in0_d3 }} skip ;;
 ADD LR9 LR14 LR6 ; SET LR10 {{ cr.panel }} ;;
{% if chunks > 1 %}
 SET LR7 LR9 ;;
{% for i in range(chunks - 1) %}
 ADD LR9 LR9 LR7 ;;
{% endfor %}
{% endif %}
chunk:
 LD.MULT R0 LR9 {{ cr.in0 }} ; SET LR11 CR0 ;;
channels:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; DEC LR10 16 ;;
{% for i in range(16) %}
 {% set cur = 'LR15' if i % 2 == 0 else 'LR12' %}
 {% set next = 'LR12' if i % 2 == 0 else 'LR15' %}
 {% if i < 15 %}LD.MULT.CYCLIC LR4 {{ cr.weights }} {{ next }} ;{% endif %} MULT.RC.VE {{ cur }} LR11 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 {% if i > 0 %}; INC LR11 1{% endif %} ;;
{% endfor %}
 INC LR11 1 ; BEQ LR10 CR0 next_tap ;;
 BLT.S LR11 LR12 channels ;;
 INC LR9 1 ; BEQ LR15 CR0 chunk ;;
skip:
 ADD LR4 LR4 {{ cr.panel }} ;;
next_tap:
 INC LR6 1 ; SET LR7 CR0 ;;
 INC LR7 {{ kw }} ;;
 BLT.S LR6 LR7 kx ;;
 INC LR5 1 ; SET LR7 CR0 ; ADD LR14 LR14 {{ cr.in0_d3 }} ;;
 INC LR7 {{ kh }} ;;
 BLT.S LR5 LR7 ky ;;
 ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.temp }} LR13 ;;
 LD.MULT R0 LR13 {{ cr.temp }} ;;
 MULT.VE LR15 CR1 0 LR15 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ; INC LR13 1 ;;
 ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.temp }} LR13 ;;
 INC LR13 1 ; DEC LR3 1 ;;
 BLT.S CR0 LR3 block ;;
 INC LR1 {{ stride }} ; INC LR2 {{ stride }} ;;
 BLT.S LR2 {{ cr.xend }} ox ;;
 {{ step('LR1', row_delta) }}
 INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.yend }} oy ;;

{# Assemble each output row from one channel and one or two columns. #}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR13 CR0 ;;
 {{ step('LR2', out0_d1) }}
 SET LR8 CR0 ;;
 {{ step('LR8', temp_pitch) }}
channel_out:
 SET LR3 LR1 ; SET LR4 CR0 ;;
 {{ step('LR4', out0_d3 // pack) }}
packed_row:
 SET LR5 CR0 ;;
 DEC LR5 1 ;;
{% for col in range(pack) %}
 SET LR6 LR3 ; SET LR7 CR0 ;;
 {% if col %}INC LR6 {{ 2 * blocks }} ;{% endif %} INC LR7 {{ out0_d2 }} ;;
gather_{{ col }}:
 LD.MULT R0 LR6 {{ cr.temp }} ;;
 MULT.EE LR0 CR1 0 LR15 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; AGG.SUM.FIRST LR5 {{ cr.one }}.L ; INC LR5 1 ;;
 LD.MULT R0 LR6 {{ cr.temp }} ; INC LR6 1 ;;
 MULT.EE LR0 CR1 0 LR15 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; AGG.SUM LR5 {{ cr.one }}.L ; DEC LR7 1 ; ADD LR6 LR6 LR8 ;;
 DEC LR6 1 ;;
 BLT.S CR0 LR7 gather_{{ col }} ;;
{% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0|default('identity') }} {{ cr.packed_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 INC LR13 1 ; INC LR3 {{ 2 * blocks * pack }} ; DEC LR4 1 ;;
 BLT.S CR0 LR4 packed_row ;;
 DEC LR2 1 ; INC LR0 1 ;;
 BLT.S LR0 LR12 channel_next ;;
 SET LR0 CR0 ; INC LR1 2 ;;
channel_next:
 BLT.S CR0 LR2 channel_out ;;
 HALT ;;
