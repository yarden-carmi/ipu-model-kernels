{% set iq = cr.qf_in0 ~ '.L' %}
{% set q = cr.qf_gamma ~ '.L' %}
{% set full = 'CR15.L' %}
{% set tail = cr.limits ~ '.L' %}
{% set one = cr.limits ~ '.H' %}
{% set B = in0_d0 %}
{% set T = in0_d1 %}
{% set C = in0_d2 %}
{% set P = B*T %}
{% set W = (P+127)//128 %}
{% macro imm(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% for bit in range(n.bit_length()-1,-1,-1) %}
 {% if not loop.first %}ADD {{ reg }} {{ reg }} {{ reg }} ;;{% endif %}
 {% if (n // (2**bit)) % 2 %}INC {{ reg }} 1 ;;{% endif %}
 {% endfor %}
{% endmacro %}
{% macro advance(reg,n) %}
 {% if n <= 255 %}{% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
 {% else %}{{ imm('LR14',n) }} ADD {{ reg }} {{ reg }} LR14 ;;{% endif %}
{% endmacro %}
{% macro vec(op,ds=full) %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}
{% endmacro %}
{% macro store(ds,ptr,act='identity') %}
 ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ q }} {{ cr.tmp }} {{ ptr }}
{% endmacro %}
{% macro split(ds,ptr) %}
 {{ store(ds,ptr) }} ;;
 LD.MULT R0 {{ ptr }} {{ cr.tmp }} ;;
 {{ vec('SUB',ds) }} ; INC {{ ptr }} 1 ; {{ store(ds,ptr) }} ;;
 INC {{ ptr }} 1 ;;
{% endmacro %}

{# Decompose the logical view's flat index into stored (batch,time,channel).
   LR7 is channel, LR11 its physical row base; LR8 is B*time+batch,
   with row and lane tracked separately in LR12 and LR13. #}
{% macro gather(label,count,ds) %}
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR15 CR0 ;;
 INC LR15 {{ count }} ;;
{{ label }}:
 ADD LR14 LR11 LR12 ;;
 LD.MULT R0 LR14 {{ cr.in0 }} ; DEC LR15 1 ;;
 MULT.EE LR13 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 7 ;;
 ADDBI LRD2 1 ;;
 {% if P % C %}
 INC LR7 {{ P % C }} ;;
 {{ advance('LR11',W*(P%C)) }}
 BLT.S LR7 {{ cr.in0_d2 }} {{ label }}_no_carry ;;
 SUB LR7 LR7 {{ cr.in0_d2 }} ; SUB LR11 LR11 {{ cr.cwidth }} ; INC LR8 {{ B }} ;;
 INC LR13 {{ B }} ;;
{{ label }}_no_carry:
 {% endif %}
 {{ advance('LR8',B*(P//C)) }}
 {{ advance('LR13',B*(P//C)) }}
 BLT.S LR8 LR9 {{ label }}_lane ;;
 SUB LR8 LR8 LR9 ; SET LR12 CR0 ;;
 INC LR8 1 ;;
 SET LR13 LR8 ;;
{{ label }}_lane:
 {% if P > 128 %}
 BLT.S LR13 LR1 {{ label }}_next ;;
{{ label }}_lane_step:
 DEC LR13 128 ; INC LR12 1 ;;
 {% if B*(P//C+1) >= 128 %}BGE.S LR13 LR1 {{ label }}_lane_step ;;{% endif %}
{{ label }}_next:
 {% endif %}
 BNE LR15 CR0 {{ label }} ;;
 {{ split(ds,'LR10') }}
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
 INC LR1 128 ;;
 {{ imm('LR9',P) }}
 {{ imm('LR10',16) }}
batch_loop:
 SET LR5 LR4 ;;
 {{ imm('LR6',T) }}
gather_row:
 SET LR7 LR5 ; SET LR8 CR0 ; SET LR12 CR0 ;;
init_time:
 BLT.S LR7 {{ cr.in0_d2 }} init_plane ;;
 SUB LR7 LR7 {{ cr.in0_d2 }} ; INC LR8 {{ B }} ; B init_time ;;
init_plane:
 SET LR13 LR8 ; SET LR11 CR0 ; SET LR14 LR7 ;;
init_channel:
 BEQ LR14 CR0 init_lane ;;
 INC LR11 {{ W }} ; DEC LR14 1 ; B init_channel ;;
init_lane:
 BLT.S LR13 LR1 gather_ready ;;
 DEC LR13 128 ; INC LR12 1 ; B init_lane ;;
gather_ready:
 {{ gather('gather_full',128,full) }}
 {{ gather('gather_tail',channels-128,tail) }}
 INC LR5 {{ B }} ; DEC LR6 1 ;;
 BNE LR6 CR0 gather_row ;;
 INC LR4 1 ;;
 {{ imm('LR14',B) }}
 BLT.S LR4 LR14 batch_loop ;;

{# Scratch rows 0:2 mean, 2:6 centered, 6 inv std, 7:9 gain. #}
 SET LR3 CR0 ; SET LR15 CR0 ; SET LR14 CR0 ;;
 INC LR3 128 ; INC LR15 16 ; SET LR13 LR10 ;;
norm_row:
 SET LR5 CR0 ; SET LR4 LR15 ; LD.MULT.CYCLIC LR5 {{ cr.crow }} LR0 ;;
 INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.crow }} LR3 ;;
 LD.MULT R0 LR4 {{ cr.tmp }} ;;
 {% for ds in [full,tail] %}
 {% set first_chunk = loop.first %}
 {% for part in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if first_chunk and part == 0 %}.FIRST{% endif %} LR0 {{ ds }} ;;
 {% if not (part == 1 and not first_chunk) %}INC LR4 1 ; LD.MULT R0 LR4 {{ cr.tmp }} ;{% endif %} MULT.RC.VV LR3 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 {% endfor %}
 SET LR6 CR0 ; {{ split(one,'LR6') }}
 SET LR4 LR15 ; SET LR6 CR0 ;;
 INC LR6 2 ;;
 {% for ds in [full,tail] %}
 LD.MULT R0 LR4 {{ cr.tmp }} ;;
 INC LR4 1 ; LD.MULT R0 LR4 {{ cr.tmp }} ; {{ vec('ADD.FIRST',ds) }} ;;
 INC LR4 1 ; LD.MULT R0 LR0 {{ cr.tmp }} ; {{ vec('ADD',ds) }} ;;
 LD.MULT R0 LR0 {{ cr.tmp }} ; MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
 SET LR5 CR1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
 {{ split(ds,'LR6') }}
 {% endfor %}

 SET LR6 CR0 ;;
 INC LR6 2 ;;
 {% for ds in [full,tail] %}
 LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
 INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR3 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 INC LR6 1 ;;
 MULT.RC.VS LR0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if loop.first %}.FIRST{% endif %} LR0 {{ ds }} ;;
 {% for _ in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 MULT.RC.VS LR3 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;
 {% endfor %}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ vec('ADD',one) }} ; {{ store(one,'LR6','rsqrt') }} ;;
 {# Refine y = rsqrt(a) with 2*y + y*(1-a*y*y), including affine scale. #}
 SET LR7 CR0 ;;
 INC LR7 9 ;;
 {{ split(one,'LR7') }}
 LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ one }} {{ q }} ; ACC.ADD.FIRST ;;
 {{ split(one,'LR7') }}
 DEC LR7 2 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
 INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR3 ;;
 SET LR5 CR1 ; LD.MULT R0 LR5 {{ cr.epsilon }} ;;
 {{ vec('ADD.FIRST',one) }} ; DEC LR7 3 ; LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {% for _ in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ one }} {{ q }} ; ACC.SUB ;;
 MULT.RC.VV LR3 R0 0 LR0 {{ one }} {{ q }} ; ACC.SUB ; {% if loop.first %}INC LR7 1 ; LD.MULT R0 LR7 {{ cr.tmp }}{% else %}{{ store(one,'LR7') }}{% endif %} ;;
 {% endfor %}
 LD.MULT R0 LR7 {{ cr.tmp }} ;;
 LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ one }} {{ q }} ; ACC.ADD.FIRST ; INC LR7 4 ; {{ store(one,'LR7') }} ;;
 LD.MULT R1 LR6 {{ cr.tmp }} ;;
 SET LR6 CR0 ;;
 INC LR6 2 ;;
 {% for ds in [full,tail] %}
 SET LR5 {{ 'CR0' if loop.first else 'CR1' }} ;;
 LD.MULT.CYCLIC LR5 {{ cr.gamma }} LR0 ;;
 INC LR5 2 ; LD.MULT.CYCLIC LR5 {{ cr.gamma }} LR3 ;;
 MULT.RC.VE LR0 LR3 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
 {% for slot in ['LR0','LR3','LR3'] %}
 MULT.RC.VE {{ slot }} LR3 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 SET LR7 CR0 ;;
 INC LR7 14 ; LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {% for slot in ['LR0','LR3'] %}
 MULT.RC.VE {{ slot }} LR0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 SET LR7 CR0 ;;
 INC LR7 7 ;;
 {{ split(ds,'LR7') }}
 LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
 INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR3 ;;
 INC LR6 1 ;;
 DEC LR7 2 ; LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {% for slot in ['LR0','LR3'] %}
 INC LR7 1 ; LD.MULT R0 LR7 {{ cr.tmp }} ; MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ; DEC LR7 1 ; LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {% endfor %}
 SET LR5 {{ 'CR0' if loop.first else 'CR1' }} ; LD.MULT R0 LR5 {{ cr.beta }} ;;
 INC LR5 2 ; LD.MULT R0 LR5 {{ cr.beta }} ; {{ vec('ADD',ds) }} ;;
 {{ vec('ADD',ds) }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ;;
 INC LR14 1 ;;
 {% endfor %}
 INC LR15 4 ;;
 BLT.S LR15 LR13 norm_row ;;
 HALT ;;
