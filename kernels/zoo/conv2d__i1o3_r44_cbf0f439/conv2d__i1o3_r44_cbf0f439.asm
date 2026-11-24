{% set full = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% macro step(reg, n) %}
{% for tile in range(0, n|abs, 8160) %}
{% for i in range(tile, [tile+8160, n|abs]|min, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ reg }} {{ [255, (n|abs)-i]|min }} ;;
{% endfor %}
{% endfor %}
{% endmacro %}

{% if narrow %}
{# A narrow output would leave most of an outer product idle. Keep the
   channel dot products, but explicitly pad the image once so the hot loop
   can run a fixed nine taps without boundary checks. #}
{% macro pad_row(label) %}
 SET LR5 CR0 ;;
 INC LR5 {{ w + 2 }} ;;
 MULT.EE LR15 CR0 0 LR15 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
{{ label }}:
 ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.temp }} LR0 ; DEC LR5 1 ;;
 INC LR0 1 ; BLT.S CR0 LR5 {{ label }} ;;
{% endmacro %}
 {{ pad_row('top') }}
pad_y:
 MULT.EE LR15 CR0 0 LR15 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.temp }} LR0 ; SET LR5 CR0 ;;
 INC LR0 1 ; INC LR5 {{ w }} ;;
copy_x:
 LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR15 ;;
 MULT.RC.VE LR15 CR1 0 LR15 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR1 1 ; DEC LR5 1 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.temp }} LR0 ;;
 INC LR0 1 ; BLT.S CR0 LR5 copy_x ;;
 MULT.EE LR15 CR0 0 LR15 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR2 1 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.temp }} LR0 ;;
 INC LR0 1 ; BLT.S LR2 {{ cr.h }} pad_y ;;
 {{ pad_row('bottom') }}

 SET LR2 CR0 ; SET LR13 CR0 ;;
 INC LR13 {{ w }} ;;
channel:
 SET LR3 CR0 ; SET LR4 CR0 ;;
packed_row:
 LD.MULT.CYCLIC LR2 {{ cr.weights }} LR15 ;;
 MULT.RC.VE LR15 {{ 'CR1' if bias else 'CR0' }} 0 LR15 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; SET LR6 CR0 ; SET LR12 CR0 ;;
 SET LR5 CR0 ;;
 INC LR12 {{ pack * wo }} ;;
pixel:
 SET LR7 LR2 ; SET LR8 LR3 ; LD.MULT.CYCLIC LR3 {{ cr.temp }} LR15 ;;
 SET LR9 LR3 ;;
 {% for y in range(3) %}
  {% for x in range(3) %}
 INC LR7 1 ; LD.MULT R0 LR7 {{ cr.weights }} ; {% if x == 2 and y != 2 %}INC LR8 {{ w + 2 }} ;{% endif %} ;;
 MULT.RC.VV LR15 R0 0 LR15 {{ full }} {{ qi }} ; AGG.SUM LR6 {{ full }}
 {% if x != 2 %}; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.temp }} LR15
 {% elif y != 2 %}; SET LR9 LR8 ; LD.MULT.CYCLIC LR8 {{ cr.temp }} LR15
 {% endif %} ;;
  {% endfor %}
 {% endfor %}
 INC LR3 1 ; INC LR5 1 ; INC LR6 1 ;;
 BLT.S LR5 LR13 pixel ;;
 INC LR3 2 ; INC LR4 1 ; SET LR5 CR0 ;;
 BLT.S LR6 LR12 pixel ;;
 ACTIVATE.QUANTIZE {{ act_out0|default('identity') }} {{ cr.packed }}.L {{ qo }} {{ cr.out0 }} LR10 ;;
 INC LR10 1 ; BLT.S LR4 {{ cr.h }} packed_row ;;
 INC LR2 10 ; INC LR11 1 ;;
 SET LR14 CR0 ;;
 INC LR14 {{ cout }} ;;
 BLT.S LR11 LR14 channel ;;
 HALT ;;
{% else %}
{# Accumulate output channels together. Each loaded input vector serves a
   whole panel of outer products with streamed weight vectors. #}
 INC LR12 128 ;;
 {{ step('LR1', origin) }}
 {{ step('LR0', -padding) }}
 {{ step('LR8', w) }}
oy:
 SET LR2 CR0 ;;
 {{ step('LR2', -padding) }}
ox:
 SET LR3 CR0 ; SET LR4 CR0 ;;
 INC LR3 {{ blocks }} ;;
block:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 MULT.RC.VE LR15 {{ 'CR1' if bias else 'CR0' }} 0 LR15 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR4 1 ; SET LR5 CR0 ; SET LR14 LR1 ;;
ky:
 SET LR6 LR2 ; SET LR9 LR14 ; ADD LR7 LR0 LR5 ;;
 BLT.S LR7 CR0 skip_y ;;
 BGE.S LR7 {{ cr.h }} skip_y ;;
 SET LR7 LR2 ;;
 INC LR7 {{ kw }} ;;
kx:
 BLT.S LR6 CR0 skip_x ;;
 BGE.S LR6 LR8 skip_x ;;
 SET LR10 {{ cr.panel }} ;;
chunk:
 LD.MULT R0 LR9 {{ cr.in0 }} ; SET LR11 CR0 ;;
channels:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; DEC LR10 16 ;;
{% for i in range(16) %}
 {% set cur = 'LR15' if i % 2 == 0 else 'LR12' %}
 {% set next = 'LR12' if i % 2 == 0 else 'LR15' %}
 {% if i < 15 %}LD.MULT.CYCLIC LR4 {{ cr.weights }} {{ next }} ;{% endif %} MULT.RC.VE {{ cur }} LR11 0 LR15 {{ full }} {{ qi }} ; ACC.ADD ; INC LR4 1 {% if i > 0 %}; INC LR11 1{% endif %} ;;
{% endfor %}
 INC LR11 1 ; BEQ LR10 CR0 last_chunk ;;
 BLT.S LR11 LR12 channels ;;
 INC LR9 1 ; B chunk ;;
last_chunk:
 INC LR9 {{ chunks - ((panel - 1) // 128) }} ; B next_x ;;
skip_y:
 {% for i in range(kw) %}ADD LR4 LR4 {{ cr.panel }} ;;{% endfor %}
 B next_y ;;
skip_x:
 ADD LR4 LR4 {{ cr.panel }} ; INC LR9 {{ chunks }} ;;
next_x:
 INC LR6 1 ;;
 BLT.S LR6 LR7 kx ;;
next_y:
 INC LR5 1 ; ADD LR14 LR14 {{ cr.ytap_step }} ; SET LR7 CR0 ;;
 INC LR7 {{ kh }} ;;
 BLT.S LR5 LR7 ky ;;
 {# Save the rounded value and its residual for the layout conversion. #}
 ACTIVATE.QUANTIZE identity {{ full }} {{ qo }} {{ cr.temp }} LR13 ;;
 LD.MULT R0 LR13 {{ cr.temp }} ;;
 MULT.VE LR15 CR1 0 LR15 {{ full }} {{ qo }} ; ACC.SUB ; INC LR13 1 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ qo }} {{ cr.temp }} LR13 ;;
 INC LR13 1 ; DEC LR3 1 ;;
 BLT.S CR0 LR3 block ;;
 {% if input_step > 255 %}
 {{ step('LR1', input_step) }}
 INC LR2 {{ stride }} ;;
 {% else %}
 INC LR1 {{ input_step }} ; INC LR2 {{ stride }} ;;
 {% endif %}
 BLT.S LR2 {{ cr.xstop }} ox ;;
 {{ step('LR1', row_delta) }}
 INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.ystop }} oy ;;

{# Gather consecutive pixels of a channel into the original width-packed
   output. For wide images, split each raster row into 128-lane segments. #}
{% macro gather(label, count, ds) %}
 SET LR5 CR0 ; SET LR7 CR0 ;;
 DEC LR5 1 ; INC LR7 {{ count }} ;;
{{ label }}:
 LD.MULT R0 LR6 {{ cr.temp }} ;;
 MULT.EE LR0 CR1 0 LR15 {{ full }} {{ qo }} ; AGG.SUM.FIRST LR5 {{ cr.one }}.L ; INC LR5 1 ; INC LR6 1 ;;
 LD.MULT R0 LR6 {{ cr.temp }} ;;
 MULT.EE LR0 CR1 0 LR15 {{ full }} {{ qo }} ; AGG.SUM LR5 {{ cr.one }}.L ; DEC LR7 1 ; INC LR6 {{ 2 * blocks - 1 }} ;;
 BLT.S CR0 LR7 {{ label }} ;;
 ACTIVATE.QUANTIZE {{ act_out0|default('identity') }} {{ ds }}.L {{ qo }} {{ cr.out0 }} LR13 ;;
 INC LR13 1 ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 SET LR2 CR0 ;;
 {{ step('LR2', cout) }}
channel_out:
 SET LR6 LR1 ; SET LR3 CR0 ;;
 {{ step('LR3', ho // pack) }}
packed_row:
{% if wo > 128 %}
 SET LR4 CR0 ;;
 INC LR4 {{ wo // 128 }} ;;
segment:
 {{ gather('gather_full', 128, cr.full) }}
 DEC LR4 1 ;;
 BLT.S CR0 LR4 segment ;;
 {% if wo % 128 %}{{ gather('gather_tail', wo % 128, cr.packed) }}{% endif %}
{% else %}
 {{ gather('gather_packed', wo * pack, cr.packed) }}
{% endif %}
 DEC LR3 1 ;;
 BLT.S CR0 LR3 packed_row ;;
 DEC LR2 1 ; INC LR0 1 ;;
 BLT.S LR0 LR12 channel_next ;;
 SET LR0 CR0 ; INC LR1 2 ;;
channel_next:
 BLT.S CR0 LR2 channel_out ;;
 HALT ;;
{% endif %}
