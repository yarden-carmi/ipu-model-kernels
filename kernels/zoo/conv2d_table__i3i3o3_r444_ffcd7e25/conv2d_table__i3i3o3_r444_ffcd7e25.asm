{% set width = out0_d3 %}
{% set full = [out0_d2, 128 // width]|min %}
{% set pack = full if out0_d2 % full == 0 else 1 %}
{% set tiles = out0_d2 // pack %}
{% set pitch = 128 if pack == 1 else width %}
{% set ds = cr.ds128 ~ '.L' %}
{% set q = cr.qf_weights ~ '.L' %}
{% set qi = cr.qf_in1 ~ '.L' %}
{% macro num(reg, n) %}
 SET {{ reg }} CR0 ;;
 {% for off in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ reg }} {{ [255, n|abs - off]|min }} ;;
 {% endfor %}
{% endmacro %}
{% macro guards() %}
 SUB LR9 LR8 CR1 ; BEQ LR6 CR0 top ;;
 LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR0 ; BEQ CR0 CR0 center ;;
top:
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ;;
center:
 LD.MULT.CYCLIC LR8 {{ cr.in1 }} LR1 ; ADD LR9 LR8 CR1 ; BEQ LR6 LR10 bottom ;;
 LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR2 ; BEQ CR0 CR0 macs ;;
bottom:
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR2 ;;
{% endmacro %}

 {{ num('LR1', 128) }}
 {{ num('LR2', 256) }}
 {{ num('LR3', 384) }}
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR3 ;;
 {{ num('LR3', -1) }}
 {% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR3 ; INC LR3 1 ;;
 {% endfor %}
 {{ num('LR4', 0) }}
 {{ num('LR5', -1) }}
 {{ num('LR10', tiles - 1) }}
 {{ num('LR11', cin - 1) }}
 {{ num('LR13', cout - 1) }}
output_channel:
 SET LR6 CR0 ;;
output_tile:
 SET LR14 LR4 ; SET LR7 CR0 ; SET LR8 LR6 ;;
 LD.MULT R0 LR14 {{ cr.weights }} ; INC LR14 1 ;;
 {% for p in range(4) %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{{ '.FIRST' if p == 0 else '' }} ; {% if p < 3 %}LD.MULT R0 LR14 {{ cr.weights }} ; INC LR14 1 ;{% endif %} ;;
 {% endfor %}
input_channel:
 {{ guards() }}
macs:
 {% for dy in [-1, 0, 1] %}
 {% for dx in [-1, 0, 1] %}
 {{ num('LR3', 128 + dy * pitch + dx) }}
 LD.MULT R0 LR14 {{ cr.weights }} ; INC LR14 1 ;;
 {% for p in range(4) %}
 MULT.RC.VV LR3 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; {% if p < 3 %}LD.MULT R0 LR14 {{ cr.weights }} ; INC LR14 1 ;{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {% endfor %}
 ADD LR8 LR8 {{ cr.tiles }} ; INC LR7 1 ; BLT.S LR7 LR11 input_channel ;;
 ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ cr.ds_pack }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR6 1 ; BLT.S LR6 LR10 output_tile ;;
 SET LR4 LR14 ; INC LR12 1 ; BLT.S LR12 LR13 output_channel ;;
 HALT ;;
