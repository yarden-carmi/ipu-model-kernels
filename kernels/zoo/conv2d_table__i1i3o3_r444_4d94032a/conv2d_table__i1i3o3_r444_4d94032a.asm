{% set width = in1_d3 %}
{% set tiles = (in1_d2 * width + 127) // 128 %}
{% set gc = cin // groups %}
{% set big = h*w >= 512 %}
{% set block = 13 if big else 3 %}
{% set qi = cr.qf_in1 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set ds = cr.ds128 ~ '.L' %}

{% macro setnum(reg, n) %}
 SET {{ reg }} CR0 ;;
 {% for k in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ reg }} {{ [255, n|abs-k]|min }} ;;
 {% endfor %}
{% endmacro %}

{% if h*w <= 64 %}
{# Two output channels share an accumulator. Duplicate each input plane,
   then use two adjacent cyclic slots for all nine spatial shifts. #}
 {{ setnum('LR0', 0) }}
 {{ setnum('LR1', 128) }}
 {{ setnum('LR2', 448) }}
 {{ setnum('LR3', -1) }}
 LD.MULT R0 LR3 {{ cr.weights }} ; INC LR3 1 ;;
 LD.MULT R1 LR3 {{ cr.weights }} ; INC LR3 1 ;;
 {{ setnum('LR4', -1) }}
 {{ setnum('LR5', cin - 1) }}
duplicate:
 LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR0 ; INC LR4 1 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 MULT.RC.VV LR2 R1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR4 ; BLT.S LR4 LR5 duplicate ;;
 {{ setnum('LR4', -1) }}
 {% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR4 ; INC LR4 1 ;;
 {% endfor %}
 {{ setnum('LR4', -1) }}
 {{ setnum('LR5', (cout // groups + 1) // 2 - 1) }}
 {{ setnum('LR6', cin) }}
 {{ setnum('LR7', -1) }}
 {{ setnum('LR8', -1) }}
 {{ setnum('LR9', groups - 1) }}
 SET LR10 CR0 ;;
 SET LR11 CR0 ;;
 {{ setnum('LR15', gc - 1) }}
 LD.MULT R0 LR3 {{ cr.weights }} ; INC LR3 1 ;;
pair_group:
 SET LR12 CR0 ;;
pair_output:
 SET LR13 LR8 ; SET LR14 CR0 ;;
 LD.MULT R0 LR3 {{ cr.weights }} ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; INC LR3 1 ;;
 LD.MULT R0 LR3 {{ cr.weights }} ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR3 1 ;;
pair_channel:
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; INC LR13 1 ; SET LR2 LR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR1 ; INC LR2 {{ 63-width }} ;;
 {% for y in range(3) %}
 {% for x in range(3) %}
 {% set first = y == 0 and x == 0 %}
 {% if not first and x != 0 %}
 {% set delta = 1 %}
 {% elif not first %}
 {% set delta = width - 2 %}
 {% else %}
 {% set delta = 0 %}
 {% endif %}
 LD.MULT R0 LR3 {{ cr.weights }} ; MULT.RC.VV LR2 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR3 1{% if delta %} ; INC LR2 {{ delta }}{% endif %} ;;
 {% if y != 1 or x != 1 %}
 LD.MULT R0 LR3 {{ cr.weights }} ; MULT.RC.VV LR2 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR3 1{% if y == 2 and x == 2 %} ; INC LR14 1 ; BLT.S LR14 LR15 pair_channel{% endif %} ;;
 {% endif %}
 {% endfor %}
 {% endfor %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf_out0 }}.L {{ cr.pad }} LR6 ;;
 LD.MULT.CYCLIC LR6 {{ cr.pad }} LR0 ;;
 LD.MULT R1 LR3 {{ cr.weights }} ; INC LR3 1 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE generic {{ cr.ds_tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ; INC LR7 1 ; LD.MULT R0 LR3 {{ cr.weights }} ; INC LR3 1 ;;
 {% if (cout // groups) % 2 %} BEQ LR12 LR5 pair_group_done ;; {% endif %}
 {{ setnum('LR2', 64) }}
 MULT.RC.VV LR2 R1 0 LR0 {{ ds }} {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE generic {{ cr.ds_tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ; INC LR7 1 ; INC LR12 1 ; BLT.S LR12 LR5 pair_output ;;
pair_group_done:
 SET LR8 LR13 ; INC LR10 1 ; BLT.S LR10 LR9 pair_group ;;
 HALT ;;
{% else %}

{# One scratch row is a guard for the first and last tile. #}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ; INC LR2 255 ; SET LR4 CR0 ;;
 INC LR2 1 ; DEC LR4 1 ; SET LR5 CR0 ;;
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR4 ; INC LR4 1 ; DEC LR5 1 ;;
 LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1 ;;
 LD.MULT R1 LR5 {{ cr.weights }} ; INC LR5 1 ;;
 SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
 DEC LR6 1 ; SET LR9 CR0 ;;
 {{ setnum('LR10', cin - 1) }}
 {{ setnum('LR11', tiles - 1) }}
stage_tile:
 SET LR5 LR6 ; SET LR8 CR0 ;;
stage_channel:
 {% if tiles > 1 %}
 BEQ LR7 CR0 top_guard ; DEC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR0 ; INC LR5 1 ; BEQ CR0 CR0 load_center ;;
top_guard:
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR0 ; INC LR5 1 ;;
 {% else %}
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR0 ;;
 {% endif %}
load_center:
 LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR1 ; INC LR5 1 ; BEQ LR7 LR11 bottom_guard ;;
 LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR2 ; INC LR5 1 ; BEQ CR0 CR0 stage_taps ;;
bottom_guard:
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR2 ; INC LR5 1 ;;
stage_taps:
 SET LR3 LR1 ;;
 DEC LR3 {{ width + 2 }} ;;
 {% for y in range(3) %}
 {% for x in range(3) %}
 MULT.RC.{{ 'VE' if x == 1 else 'VV' }} LR3 {{ ['R0','CR1','R1'][x] }} 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1 ; INC LR3 {{ width - 2 if y and not x else 1 }} ;;
 {% endfor %}
 {% endfor %}
 ADD LR5 LR5 {{ cr.tiles }} ;;
 DEC LR5 2 ; INC LR8 1 ; BLT.S LR8 LR10 stage_channel ;;
 INC LR6 1 ; INC LR7 1 ; BLT.S LR7 LR11 stage_tile ;;
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1 ;;

{# Scalar coefficient blocks amortize a weight load over up to 126 taps.
   The cyclic input prefetch, pointer advances and MAC share a word. #}
{% macro macs(n, again=false, more=false) %}
 LD.MULT R0 LR2 {{ cr.weights }} ; INC LR2 1 ; SET LR3 CR0 ; SET LR15 CR0 ;;
 LD.MULT R1 LR2 {{ cr.weights }} ; INC LR2 1 ; DEC LR3 1 ; INC LR15 127 ;;
 {% for c in range(n) %}
 {% for tap in range(9) %}
 {% set last = c == n-1 and tap == 8 %}
 {% if (big and tap != 8) or (not big and (c + tap + 1) % 3 == 0) %}
 MULT.RC.VE LR0 LR15 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR15 1 ;;
 {% endif %}
 MULT.RC.VE LR0 LR3 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR3 1{% if not last or more or again %} ; LD.MULT.CYCLIC LR1 {{ cr.pad }} LR0 ; INC LR1 1{% endif %}{% if last and again %} ; INC LR8 1 ; BLT.S LR8 LR9 coeff_block{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}

 {{ setnum('LR2', -1) }}
 {% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR2 ; INC LR2 1 ;;
 {% endfor %}
 {{ setnum('LR4', 1) }}
 {{ setnum('LR5', 0) }}
 {{ setnum('LR11', tiles - 1) }}
 {{ setnum('LR14', -1) }}
 {{ setnum('LR9', gc // block - 1) }}
 {{ setnum('LR6', groups - 1) }}
 SET LR7 CR0 ;;
group_loop:
 {{ setnum('LR10', cout // groups - 1) }}
channel_loop:
 SET LR12 LR5 ; SET LR13 CR0 ;;
tile_loop:
 SET LR2 LR4 ; SET LR1 LR12 ; SET LR8 CR0 ;;
 LD.MULT R0 LR2 {{ cr.weights }} ; INC LR2 1 ; SET LR3 CR0 ;;
 MULT.EE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT R1 LR2 {{ cr.weights }} ; INC LR2 1 ;;
 INC LR3 128 ; LD.MULT.CYCLIC LR1 {{ cr.pad }} LR0 ; INC LR1 1 ;;
 MULT.EE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
 {% if gc >= block %}
coeff_block:
 {{ macs(block, again=true) }}
 {% endif %}
 {% if gc % block %}
 {{ macs(gc % block) }}
 {% endif %}
 {% if out0_d2 * out0_d3 % 128 and tiles > 1 %}
 BEQ LR13 LR11 tail_store ;;
 {% endif %}
 ACTIVATE.QUANTIZE generic {{ cr.ds_tail ~ '.L' if tiles == 1 else ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR14 1 ; INC LR13 1 ; ADD LR12 LR12 {{ cr.tstep }} ; BLT.S LR13 LR11 tile_loop ;;
 {% if out0_d2 * out0_d3 % 128 and tiles > 1 %}
 BEQ CR0 CR0 channel_done ;;
tail_store:
 ACTIVATE.QUANTIZE generic {{ cr.ds_tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR14 1 ;;
channel_done:
 {% endif %}
 SET LR4 LR2 ; DEC LR10 1 ; BLT.S CR0 LR10 channel_loop ;;
 ADD LR5 LR5 {{ cr.gstep }} ; INC LR7 1 ; BLT.S LR7 LR6 group_loop ;;
 HALT ;;
{% endif %}
