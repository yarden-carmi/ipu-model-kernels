{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% set slots = ['LR0','LR3','LR4'] %}
{% set plane = in0_d0 * in0_d1 %}
{% set tiles = (plane + 127) // 128 %}
{% macro at(reg,n=0) %}
 SET {{ reg }} CR0 ;;
 {% for i in range((n+254)//255) %}INC {{ reg }} {{ [255,n-255*i]|min }} ;;{% endfor %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',fmt=q) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %}
{% endmacro %}
{% macro mac(slot='LR0',first=false) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 {{ at('LR1',n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro parts(n) %}
 {{ at('LR1',n) }}
 {% for slot in slots %}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }}{% if not loop.first %} ; INC LR1 1{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro encode(reg,pieces,ds=full) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% for i in range(pieces-1) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ; INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}{{ at('LR1',n) }}{{ encode('LR1',pieces) }}{% endmacro %}
{% macro average() %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}{{ parts(3) }}
 SET LR10 CR0 ; LD.MULT R0 LR10 {{ cr.crow }} ;;
 {% for i in range(3) %}
 {% for slot in slots %}
 {{ mac(slot,i == 0 and loop.first) }}{% if loop.last and i < 2 %} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.crow }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro product(a,b,dest) %}
 {{ at('LR7',a) }}{{ at('LR10',b) }}
 LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ mac(first=true) }} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ mac() }} ; INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ; DEC LR10 1 ;;
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ mac() }} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% if a == 11 %}
 {{ mac() }} ; INC LR7 10 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ; DEC LR10 1 ;;
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% endif %}
 {{ mac() }} ;;
 {{ save(dest) }}
{% endmacro %}
{% macro reset() %}SET LR5 CR0 ; SET LR9 CR0 ;; INC LR9 32 ;;{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
 INC LR2 1 ;;
{% endmacro %}

{% macro times(dst,src,n) %}
 SET {{ dst }} CR0 ;;
 {% for b in range(19,-1,-1) %}
 {% if (n // (2**b)) > 0 %}
 {% if (n // (2**b)) > 1 %}ADD {{ dst }} {{ dst }} {{ dst }} ;;{% endif %}
 {% if (n // (2**b)) % 2 %}ADD {{ dst }} {{ dst }} {{ src }} ;;{% endif %}
 {% endif %}
 {% endfor %}
{% endmacro %}

{# The view offset is p = batch + d0*spatial + channel*plane.
   Decode p in canonical [batch, spatial, channel] storage, then pack
   those coordinates into the writer's [channel, spatial, batch] rows. #}
row_loop:
 SET LR8 LR15 ; SET LR11 CR0 ; SET LR10 CR0 ;;
 {{ at('LR6',channels) }}
view_start:
 BLT.S LR8 LR6 view_start_ready ;;
 SUB LR8 LR8 LR6 ; INC LR10 1 ; BEQ LR0 CR0 view_start ;;
view_start_ready:
 {{ times('LR12','LR8',tiles) }}
gather_chunk:
 {{ scalar(first=true,imm='CR0') }} ; SET LR4 CR0 ; SET LR5 CR0 ;;
 {{ at('LR9',128) }}
gather_lane:
 SET LR8 LR10 ; SET LR1 CR0 ;;
 {{ at('LR7',in0_d1) }}
view_batch:
 BLT.S LR8 LR7 view_spatial ;;
 SUB LR8 LR8 LR7 ; INC LR1 1 ; BEQ LR0 CR0 view_batch ;;
view_spatial:
 {{ times('LR7','LR8',in0_d0) }}
 ADD LR8 LR7 LR1 ; SET LR7 LR12 ;;
 {{ at('LR1',128) }}
view_tile:
 BLT.S LR8 LR1 view_load ;;
 DEC LR8 128 ; INC LR7 1 ; BEQ LR0 CR0 view_tile ;;
view_load:
 SET LR1 CR0 ;;
 LD.MULT R0 LR7 {{ cr.in0 }} ;;
 MULT.EE LR8 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD4 7 ; DEC LR6 1 ; DEC LR9 1 ;;
 ADDBI LRD4 1 ;;
 BEQ LR6 CR0 gather_last ;;
 {% if (plane // channels) %}
 {{ at('LR7',plane // channels) }}
 ADD LR10 LR10 LR7 ;;
 {% endif %}
 {% if plane % channels %}
 {{ at('LR7',(plane % channels) * tiles) }}
 ADD LR12 LR12 LR7 ;;
 BLT.S LR12 {{ cr.channel_span }} view_step_done ;;
 SUB LR12 LR12 {{ cr.channel_span }} ; INC LR10 1 ;;
view_step_done:
 {% endif %}
 BLT.S CR0 LR9 gather_lane ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ iq }} {{ cr.gathered }} LR11 ;;
 INC LR11 1 ; BEQ LR0 CR0 gather_chunk ;;
gather_last:
 ACTIVATE.QUANTIZE identity {{ tail }} {{ iq }} {{ cr.gathered }} LR11 ;;
 {{ at('LR3',128) }}
 ADD LR4 LR3 LR3 ;;

 SET LR6 LR11 ; SET LR5 CR0 ; {{ scalar(first=true,imm='CR0') }} ;;
 BEQ LR5 LR6 sum_tail ;;
sum_loop:
 LD.MULT R0 LR5 {{ cr.gathered }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; AGG.SUM LR0 {{ full }} ; INC LR5 1 ;;
 BLT.S LR5 LR6 sum_loop ;;
sum_tail:
 LD.MULT R0 LR5 {{ cr.gathered }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ iq }} ; AGG.SUM LR0 {{ tail }} ;;
 {{ average() }}{{ save(27,3) }}

 {{ parts(27) }}{{ reset() }}
center_loop:
 LD.MULT R0 LR5 {{ cr.gathered }} ;;
 {{ scalar(first=true,fmt=iq) }} ;;
 {% for slot in slots %}
 MULT.RC.VE {{ slot }} CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
 {% endfor %}
 BEQ LR5 LR6 center_tail ;;
 {{ encode('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ; BEQ LR0 CR0 center_loop ;;
center_tail:
 {{ encode('LR9',2,tail) }}

 {{ reset() }}{{ scalar(first=true,imm='CR0') }} ;;
 INC LR6 1 ;;
variance_loop:
 SET LR1 LR9 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% for i in range(2) %}
 SET LR10 LR9 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% for j in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }}
 {% if j == 0 %} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }}
 {% elif i == 0 %} ; INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0
 {% else %} ; INC LR9 2 ; INC LR5 1{% endif %} ;;
 {% endfor %}
 {% endfor %}
 BLT.S LR5 LR6 variance_loop ;;
 {{ average() }}
 INC LR10 1 ; LD.MULT R0 LR10 {{ cr.crow }} ;;
 {{ scalar() }} ;;
 {{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ;;{{ save(22,1) }}

 {# Two Newton corrections, retaining residual components. #}
 {{ load(8,true) }}{{ load(8) }}{{ mac(first=true) }} ;;{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mac(first=true) }} ;;
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac() }} ;;{{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }} ;;{% endfor %}
 {{ save(19) }}
 {{ product(19,19,13) }}{{ product(11,13,15) }}{{ product(19,15,17) }}
 {% for n in [19,20] %}
 {{ load(n,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }} ;;{% endfor %}
 {{ save(19) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ;;{{ save(21,1) }}

 {{ reset() }}{{ parts(19) }}
 ADD LR12 LR4 LR3 ; SET LR7 LR6 ; DEC LR6 1 ;;
output_loop:
 SET LR10 LR5 ; LD.MULT R0 LR10 {{ cr.gamma }} ;;
 {% for i in range(3) %}
 {% for slot in slots %}
 {{ mac(slot,i == 0 and loop.first) }}{% if loop.last and i < 2 %} ; ADD LR10 LR10 LR7 ; LD.MULT R0 LR10 {{ cr.gamma }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ save(9) }}
 LD.MULT R1 LR1 {{ cr.tmp }} ;;
 DEC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR12 ;;
 {% for i in range(2) %}
 {% for j in range(2) %}
 MULT.RC.VV LR12 R{{ j }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and j == 0 %}.FIRST{% endif %}{% if j == 1 %} ; INC LR9 1{% if i == 0 %} ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR12{% endif %}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 SET LR10 LR5 ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {% for i in range(3) %}
 {{ scalar() }}{% if not loop.last %} ; ADD LR10 LR10 LR7 ; LD.MULT R0 LR10 {{ cr.beta }}{% endif %} ;;
 {% endfor %}
 BEQ LR5 LR6 output_tail ;;
 {{ store(full) }}
 INC LR5 1 ; BEQ LR0 CR0 output_loop ;;
output_tail:
 {{ store(tail) }}
 BEQ LR2 {{ cr.M }} finished ;;
 {{ at('LR1',in0_d1) }}
 INC LR14 1 ; INC LR15 {{ in0_d0 }} ;;
 BNE LR14 LR1 row_loop ;;
 SET LR14 CR0 ; INC LR13 1 ;;
 SET LR15 LR13 ; BEQ LR0 CR0 row_loop ;;
finished:
 HALT ;;
