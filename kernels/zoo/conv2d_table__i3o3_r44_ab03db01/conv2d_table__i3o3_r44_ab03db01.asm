{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.ds128 ~ '.L' %}
{% set strip = cr.ds_strip ~ '.L' %}
{% set ow = out0_d3 %}
{% set pack = 128 // ow %}
{% set ix = (w+127)//128 %}
{% set dense = groups == 1 %}
{% set direct = dense and pack > 1 and stride == 1 %}
{% set gc = cin // groups %}
{% set oc = cout // groups %}
{% set blocks = (cout+pack-1)//pack %}
{% macro num(r, n) %}
 SET {{ r }} CR0 ;;
 {% for i in range(0,n|abs,255) %}
 {{ 'INC' if n>0 else 'DEC' }} {{ r }} {{ [255,n|abs-i]|min }} ;;
 {% endfor %}
{% endmacro %}
SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
{{ num('LR4', -1) }}
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
 INC LR0 1 ;;
{% endfor %}
SET LR0 CR0 ;;
MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR0 ;;
output_y:
SET LR5 CR0 ; SET LR6 CR0 ; SET LR1 CR1 ;;
{{ num('LR11',128) }}
{{ num('LR12',256) }}
{{ num('LR13',384) }}
LD.MULT.CYCLIC LR0 {{ cr.pad }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.pad }} LR12 ;;
LD.MULT.CYCLIC LR0 {{ cr.pad }} LR13 ;;
stage_c:
SET LR7 CR0 ; SET LR8 LR2 ;;
DEC LR8 {{ ix }} ;;
stage_y:
BLT.S LR8 CR0 zero_y ;;
BLT.S LR8 {{ cr.iplane }} valid_y ;;
zero_y:
LD.MULT.CYCLIC LR0 {{ cr.pad }} LR11 ;;
{% if ix == 2 %} LD.MULT.CYCLIC LR0 {{ cr.pad }} LR12 ;; {% endif %}
BEQ CR0 CR0 stage_x ;;
valid_y:
ADD LR9 LR5 LR8 ;;
LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR11 ;;
{% if ix == 2 %} LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR12 ; INC LR9 1 ;; {% endif %}
stage_x:
{% for x in range(-1,2) %}
 SET LR10 LR11 ;;
 {% if x %} {{ 'INC' if x>0 else 'DEC' }} LR10 1 ;; {% endif %}
 {% if direct %}
  {{ num('LR14',(x+1)*pack-1) }}
  LD.MULT R0 LR14 {{ cr.weights }} ; INC LR14 1 ;;
  {% for p in range(pack) %}
   MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;
   {% if not loop.first %} DEC LR10 {{ ow }} ; {% endif %}
   {% if not loop.last %} LD.MULT R0 LR14 {{ cr.weights }} ; INC LR14 1 ;
   {% else %} ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR1 ; INC LR1 1 ; {% endif %} ;;
  {% endfor %}
 {% else %}
 {{ num('LR14', x+1) }}
 LD.MULT R0 LR14 {{ cr.weights }} ;;
 {% if stride == 1 %}
  MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 {% else %}
  MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;
  {% if ix == 2 %}
   ;;
   SET LR14 CR1 ;; INC LR14 1 ;;
   MULT.RC.VE LR10 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR14 ; INC LR10 128 ;
  {% endif %}
 {% endif %}
 {% if dense and pack > 1 %}
  ACTIVATE.QUANTIZE identity {{ strip }} {{ qi }} {{ cr.pad }} LR14 ; SET LR15 CR0 ; SET LR14 CR1 ;;
  LD.MULT.CYCLIC LR14 {{ cr.pad }} LR15 ;;
  {{ num('LR14',2) }}
  LD.MULT R0 LR14 {{ cr.weights }} ; INC LR14 1 ;;
  {% for p in range(pack) %}
   MULT.RC.VV LR15 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;
   {% if not loop.first %} DEC LR15 {{ ow }} ; {% endif %}
   {% if not loop.last %} LD.MULT R0 LR14 {{ cr.weights }} ; INC LR14 1 ;
   {% else %} ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR1 ; INC LR1 1 ; {% endif %} ;;
  {% endfor %}
 {% else %}
  ACTIVATE.QUANTIZE identity {{ strip }} {{ qi }} {{ cr.pad }} LR1 ; INC LR1 1 ;;
 {% endif %}
 {% endif %}
{% endfor %}
SET LR10 CR1 ;; INC LR10 1 ;;
INC LR8 {{ ix }} ; INC LR7 1 ; BLT.S LR7 LR10 stage_y ;;
{{ num('LR10',cin-1) }}
ADD LR5 LR5 {{ cr.iplane }} ; INC LR6 1 ; BLT.S LR6 LR10 stage_c ;;

{{ num('LR5',3*pack-1 if direct else (2+pack if dense and pack > 1 else 2)) }}
SET LR6 CR0 ; SET LR7 CR1 ; SET LR13 CR0 ;;
output_block:
{% if dense %} SET LR7 CR1 ;; {% endif %}
LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1 ;;
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT R1 LR5 {{ cr.weights }} ; INC LR5 1 ;;
MULT.VE LR11 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR15 CR0 ; SET LR10 CR0 ;;
output_strip:
SET LR8 LR7 ; SET LR9 CR0 ;;
input_channel:
LD.MULT.CYCLIC LR8 {{ cr.pad }} LR0 ; INC LR8 1 ;;
LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1 ;;
{% for t in range(9) %}
 MULT.RC.VV LR15 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1 ;;
 MULT.RC.VV LR15 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
 {% if not loop.last %} LD.MULT.CYCLIC LR8 {{ cr.pad }} LR0 ; INC LR8 1 ; {% endif %} ;;
 {% if not loop.last %} LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1 ;; {% endif %}
{% endfor %}
{% if gc > 1 %}
 {{ num('LR14',gc-1) }}
 INC LR9 1 ; BLT.S LR9 LR14 input_channel ;;
{% endif %}
{% if not dense %}
 {% if oc > 1 %}
  {{ num('LR14',oc-1) }}
  INC LR13 1 ; BLT.S LR13 LR14 keep_group ;;
 {% endif %}
 ADD LR7 LR7 {{ cr.groupstep }} ; SET LR13 CR0 ;;
 {% if oc > 1 %} keep_group: {% endif %}
 {{ num('LR14',pack-1) }}
 DEC LR15 {{ ow }} ; INC LR10 1 ; BLT.S LR10 LR14 output_strip ;;
{% endif %}
ACTIVATE.QUANTIZE generic {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ; INC LR4 1 ;;
{{ num('LR14',blocks-1) }}
INC LR6 1 ; BLT.S LR6 LR14 output_block ;;
{{ num('LR14',out0_d2-1) }}
INC LR2 {{ ix*stride }} ; INC LR3 1 ; BLT.S LR3 LR14 output_y ;;
HALT ;;
