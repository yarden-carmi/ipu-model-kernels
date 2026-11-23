{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set packs = (in0_d2 * in0_d3 + 127) // 128 %}
{% macro imm(reg, n) %}
 SET {{ reg }} CR0 ;;
 {% for i in range(0, n, 255) %}
 INC {{ reg }} {{ [n-i, 255]|min }} ;;
 {% endfor %}
{% endmacro %}

{# Copy packed planes, inserting shared zero guards between planes. #}
 SET LR0 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
 SET LR8 CR0 ; DEC LR3 1 ; DEC LR4 1 ;;
 {{ imm('LR9', packs - 1) }}
 {{ imm('LR10', cin - 1) }}
copy_plane:
 SET LR7 CR0 ;;
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR4 1 ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.guard }} LR4 ;;
copy_pack:
 LD.MULT R0 LR3 {{ cr.in0 }} ; INC LR3 1 ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR4 1 ; INC LR7 1 ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.guard }} LR4 ; BLT.S LR7 LR9 copy_pack ;;
 INC LR8 1 ; BLT.S LR8 LR10 copy_plane ;;
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR4 1 ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.guard }} LR4 ;;

{# Generate nine border-correct vectors per pack. #}
 {{ imm('LR1', 128) }}
 {{ imm('LR2', 256) }}
 SET LR3 CR0 ; SET LR4 CR1 ; SET LR5 CR1 ;;
 INC LR5 1 ; SET LR6 CR0 ; SET LR8 CR0 ;;
 DEC LR6 1 ;;
 {% macro shift(ky, kx) %}
 {% set base = 128 + ky * in0_d3 %}
 SET LR11 {{ ['LR0','LR1','LR2'][base // 128] }} ; SET LR12 CR0 ;;
 {% if base % 128 + kx > 0 %} INC LR11 {{ base % 128 + kx }} ;
 {% elif base % 128 + kx < 0 %} DEC LR11 1 ; {% endif %}
 {% if kx != -1 %} INC LR12 {{ kx + 1 }} ; {% endif %}
 LD.MULT R0 LR12 {{ cr.weights }} ;;
 MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR6 1 ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.patch }} LR6 ;;
 {% endmacro %}
patch_plane:
 SET LR7 CR0 ;;
patch_pack:
 LD.MULT.CYCLIC LR3 {{ cr.guard }} LR0 ;;
 LD.MULT.CYCLIC LR4 {{ cr.guard }} LR1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.guard }} LR2 ;;
 {% for y in range(-1, 2) %}
 {% for x in range(-1, 2) %} {{ shift(y, x) }} {% endfor %}
 {% endfor %}
 INC LR3 1 ; INC LR4 1 ; INC LR5 1 ;;
 INC LR7 1 ; BLT.S LR7 LR9 patch_pack ;;
 INC LR3 1 ; INC LR4 1 ; INC LR5 1 ;;
 INC LR8 1 ; BLT.S LR8 LR10 patch_plane ;;

 SET LR2 CR0 ;;
 DEC LR2 1 ;;
 {% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR2 ; INC LR2 1 ;;
 {% endfor %}

 SET LR7 CR0 ; SET LR9 CR0 ; SET LR11 CR0 ;;
 DEC LR11 1 ; SET LR12 CR1 ;;
 INC LR12 2 ;;
 {{ imm('LR14', packs - 1) }}
 {{ imm('LR15', cout) }}
 {% if groups > 1 %} {{ imm('LR8', cout // groups) }} {% endif %}
out_channel:
 SET LR10 LR9 ; SET LR13 CR0 ;;
out_pack:
 SET LR5 LR12 ; SET LR4 LR10 ; SET LR6 CR0 ;;
 LD.MULT R0 LR5 {{ cr.weights }} ; SET LR3 LR1 ; SET LR2 CR0 ;;
 MULT.EE LR2 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT R1 LR5 {{ cr.weights }} ; INC LR5 1 ;;
 MULT.EE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
in_channel:
 LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1 ; SET LR2 CR0 ;;
 LD.MULT R1 LR5 {{ cr.weights }} ; INC LR5 1 ; SET LR3 LR1 ;;
 LD.MULT.CYCLIC LR4 {{ cr.patch }} LR0 ; DEC LR3 1 ;;
 {# Both products must read the same tap. Prefetch into the alternate slot. #}
 {% for t in range(9) %}
 {% set slot = 'LR0' if t % 2 == 0 else 'LR1' %}
 {% set nextslot = 'LR1' if t % 2 == 0 else 'LR0' %}
 MULT.RC.VE {{ slot }} LR2 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
 {% if t < 8 %} LD.MULT.CYCLIC LR4 {{ cr.patch }} {{ nextslot }} ; INC LR4 1 ; {% endif %} ;;
 MULT.RC.VE {{ slot }} LR3 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR3 1 ;
 {% if t == 8 %}
 INC LR6 1 ; ADD LR4 LR4 {{ cr.plane }} ;;
 DEC LR4 8 ; BLT.S LR6 {{ cr.gcin }} in_channel ;;
 {% else %}
 INC LR2 1 ;;
 {% endif %}
 {% endfor %}
 {% if out0_d2 * out0_d3 % 128 %}
 BEQ LR13 LR14 tail_pack ;;
 {% endif %}
 ACTIVATE.QUANTIZE generic {{ ds }} {{ qo }} {{ cr.out0 }} LR11 ; INC LR11 1 ;
 INC LR10 9 ; INC LR13 1 ; BLT.S LR13 LR14 out_pack ;;
 {% if out0_d2 * out0_d3 % 128 %}
tail_pack:
 ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ qo }} {{ cr.out0 }} LR11 ; INC LR11 1 ;;
 {% endif %}
 SET LR12 LR5 ; INC LR7 1 ;;
 INC LR12 1 ;;
 {% if groups > 1 %}
 BLT.S LR7 LR8 same_group ;;
 ADD LR9 LR9 {{ cr.groupstep }} ;;
 {% for i in range(0, cout // groups, 255) %} INC LR8 {{ [cout // groups-i, 255]|min }} ;; {% endfor %}
same_group:
 {% endif %}
 BLT.S LR7 LR15 out_channel ;;
 HALT ;;
