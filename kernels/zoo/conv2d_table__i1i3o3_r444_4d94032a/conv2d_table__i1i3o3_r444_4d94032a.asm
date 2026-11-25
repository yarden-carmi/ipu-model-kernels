{% set w = in1_d3 %}
{% set tiles = (in1_d2*w+127)//128 %}
{% set small = h*w <= 64 %}
{% set big = h*w >= 512 %}
{% set block = 12 if big else 3 %}
{% set ds = cr.ds128 ~ '.L' %}
{% set tail = cr.ds_tail ~ '.L' %}
{% set qi = cr.qf_in1 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% macro init(r,n) %}
 SET {{r}} CR0 ;;
 {% for k in range(0,n|abs,255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{r}} {{ [255,n|abs-k]|min }} ;;
 {% endfor %}
{% endmacro %}
{{ init('LR4',-1) }}
{% for i in range(5) %}
 LD.LUT {{i}} {{cr.lut}} LR4 ; INC LR4 1 ;;
{% endfor %}
{% if small %}
{# Duplicate each input plane to process two output channels per MAC. #}
{{ init('LR0',0) }}
{{ init('LR1',128) }}
{{ init('LR2',448) }}
{{ init('LR3',-1) }}
 LD.MULT R0 LR3 {{cr.weights}} ; INC LR3 1 ;;
 LD.MULT R1 LR3 {{cr.weights}} ; INC LR3 1 ;;
{{ init('LR4',-1) }}
{{ init('LR5',cin-1) }}
duplicate:
 LD.MULT.CYCLIC LR4 {{cr.in1}} LR0 ; INC LR4 1 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ;;
 MULT.RC.VV LR2 R1 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR4 ; BLT.S LR4 LR5 duplicate ;;
{{ init('LR5',(cout+1)//2-1) }}
{{ init('LR6',cin) }}
{{ init('LR7',-1) }}
{{ init('LR12',0) }}
{{ init('LR15',cin-1) }}
 LD.MULT R0 LR3 {{cr.weights}} ; INC LR3 1 ;;
pair:
 SET LR13 CR0 ; SET LR14 CR0 ;;
 DEC LR13 1 ;;
{% for j in range(2) %}
 LD.MULT R0 LR3 {{cr.weights}} ; MULT.VE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD{{ '.FIRST' if j == 0 else '' }} ; INC LR3 1 ;;
{% endfor %}
pair_input:
 LD.MULT.CYCLIC LR13 {{cr.pad}} LR0 ; INC LR13 1 ; SET LR2 LR0 ;;
 LD.MULT.CYCLIC LR13 {{cr.pad}} LR1 ; INC LR2 {{63-w}} ;;
{% for t in range(9) %}
 {% set delta = 0 if t == 0 else (w-2 if t%3 == 0 else 1) %}
 LD.MULT R0 LR3 {{cr.weights}} ; MULT.RC.VV LR2 R0 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; INC LR3 1{% if delta %} ; INC LR2 {{delta}}{% endif %} ;;
 {% if t != 4 %}
 LD.MULT R0 LR3 {{cr.weights}} ; MULT.RC.VV LR2 R0 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; INC LR3 1{% if t == 8 %} ; INC LR14 1 ; BLT.S LR14 LR15 pair_input{% endif %} ;;
 {% endif %}
{% endfor %}
 ACTIVATE.QUANTIZE identity {{ds}} {{qo}} {{cr.pad}} LR6 ;;
 LD.MULT.CYCLIC LR6 {{cr.pad}} LR0 ;;
 LD.MULT R1 LR3 {{cr.weights}} ; INC LR3 1 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ds}} {{qo}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE generic {{tail}} {{qo}} {{cr.out0}} LR7 ; INC LR7 1 ; LD.MULT R0 LR3 {{cr.weights}} ; INC LR3 1 ;;
{% if cout%2 %} BEQ LR12 LR5 finish ;; {% endif %}
{{ init('LR2',64) }}
 MULT.RC.VV LR2 R1 0 LR0 {{ds}} {{qo}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE generic {{tail}} {{qo}} {{cr.out0}} LR7 ; INC LR7 1 ; INC LR12 1 ; BLT.S LR12 LR5 pair ;;
finish:
 HALT ;;
{% else %}
{# Stage shifted, border-masked input vectors once per spatial tile. #}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ; INC LR2 255 ; SET LR4 CR0 ;;
 INC LR2 1 ; DEC LR4 1 ; SET LR5 CR0 ;;
 MULT.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR4 ; INC LR4 1 ; DEC LR5 1 ;;
 LD.MULT R0 LR5 {{cr.weights}} ; INC LR5 1 ;;
 LD.MULT R1 LR5 {{cr.weights}} ; INC LR5 1 ;;
{{ init('LR6',-1) }}
 SET LR7 CR0 ; SET LR9 CR0 ;;
{{ init('LR10',cin-1) }}
{{ init('LR11',tiles-1) }}
stage_tile:
 SET LR5 LR6 ; SET LR8 CR0 ;;
stage_input:
{% if tiles > 1 %}
 BEQ LR7 CR0 top_guard ; DEC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{cr.in1}} LR0 ; INC LR5 1 ; BEQ CR0 CR0 center ;;
top_guard:
 LD.MULT.CYCLIC LR4 {{cr.pad}} LR0 ; INC LR5 1 ;;
{% else %}
 LD.MULT.CYCLIC LR4 {{cr.pad}} LR0 ;;
{% endif %}
center:
 LD.MULT.CYCLIC LR5 {{cr.in1}} LR1 ; INC LR5 1 ; BEQ LR7 LR11 bottom_guard ;;
 LD.MULT.CYCLIC LR5 {{cr.in1}} LR2 ; INC LR5 1 ; BEQ CR0 CR0 taps ;;
bottom_guard:
 LD.MULT.CYCLIC LR4 {{cr.pad}} LR2 ; INC LR5 1 ;;
taps:
 SET LR3 LR1 ;;
 DEC LR3 {{w+2}} ;;
{% for t in range(9) %}
 MULT.RC.{{ 'VE' if t%3 == 1 else 'VV' }} LR3 {{ ['R0','CR1','R1'][t%3] }} 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR9 ; INC LR9 1 ; INC LR3 {{w-2 if t and t%3 == 0 else 1}} ;;
{% endfor %}
 ADD LR5 LR5 {{cr.tiles}} ;;
 DEC LR5 2 ; INC LR8 1 ; BLT.S LR8 LR10 stage_input ;;
 INC LR6 1 ; INC LR7 1 ; BLT.S LR7 LR11 stage_tile ;;
 MULT.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR9 ; INC LR9 1 ;;

{# Pack many scalar coefficients into each loaded row. Prefetch the next
   staged input in the same word as the leading coefficient MAC. #}
{% macro macs(n,again=false) %}
 LD.MULT R0 LR2 {{cr.weights}} ; INC LR2 1 ; SET LR3 CR0 ; SET LR15 CR0 ;;
 LD.MULT R1 LR2 {{cr.weights}} ; INC LR2 1 ; DEC LR3 1 ; INC LR15 127 ;;
 {% for c in range(n) %}
 {% for t in range(9) %}
 {% set last = c == n-1 and t == 8 %}
 {% if big or t in [1,3,4,5,7] or (c == 0 and t == 0) %}
 MULT.RC.VE LR0 LR15 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; INC LR15 1 ;;
 {% endif %}
 MULT.RC.VE LR0 LR3 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; INC LR3 1{% if not last or again %} ; LD.MULT.CYCLIC LR1 {{cr.pad}} LR0 ; INC LR1 1{% endif %}{% if last and again %} ; INC LR8 1 ; BLT.S LR8 LR9 coeff_block{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{{ init('LR4',1) }}
{{ init('LR14',-1) }}
{{ init('LR9',cin//block-1) }}
{{ init('LR10',cout-1) }}
channel:
 SET LR12 CR0 ; SET LR13 CR0 ;;
tile:
 SET LR2 LR4 ; SET LR1 LR12 ; SET LR8 CR0 ;;
 LD.MULT R0 LR2 {{cr.weights}} ; INC LR2 1 ; SET LR3 CR0 ;;
 MULT.EE LR3 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD.FIRST ; LD.MULT R1 LR2 {{cr.weights}} ; INC LR2 1 ;;
 INC LR3 128 ; LD.MULT.CYCLIC LR1 {{cr.pad}} LR0 ; INC LR1 1 ;;
 MULT.EE LR3 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ;;
{% if cin >= block %}
coeff_block:
 {{ macs(block,true) }}
{% endif %}
{% if cin%block %} {{macs(cin%block)}} {% endif %}
{% if out0_d2*out0_d3%128 %} BEQ LR13 LR11 tail_store ;; {% endif %}
 ACTIVATE.QUANTIZE generic {{ds}} {{qo}} {{cr.out0}} LR14 ; INC LR14 1 ; INC LR13 1 ; ADD LR12 LR12 {{cr.tstep}} ; BLT.S LR13 LR11 tile ;;
{% if out0_d2*out0_d3%128 %}
 BEQ CR0 CR0 channel_done ;;
tail_store:
 ACTIVATE.QUANTIZE generic {{tail}} {{qo}} {{cr.out0}} LR14 ; INC LR14 1 ;;
channel_done:
{% endif %}
 SET LR4 LR2 ; DEC LR10 1 ; BLT.S CR0 LR10 channel ;;
 HALT ;;
{% endif %}
