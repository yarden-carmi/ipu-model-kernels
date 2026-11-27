{% set oc = (cout + 127)//128 %}
{% set wp = in0_d3 + 2*padding %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% macro imm(r,n) %}
 SET {{ r }} CR0 ;;
 {% for bit in range(23,-1,-1) if n >= 2**bit %}
 {% if n >= 2**(bit+1) %}ADD {{ r }} {{ r }} {{ r }} ;;{% endif %}
 {% if (n//(2**bit))%2 %}INC {{ r }} 1 ;;{% endif %}
 {% endfor %}
{% endmacro %}
{% macro step(r,n) %}
 {% for k in range(0,n,255) %}INC {{ r }} {{ [255,n-k]|min }} ;;{% endfor %}
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; DEC LR13 1 ;;
 {% for i in range(5) %}LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;{% endfor %}
 SET LR2 CR0 ; SET LR3 CR0 ;;
chunk:
 {# Clear padded plane, then transpose one input pixel at a time into it. #}
 SET LR9 CR0 ; SET LR10 CR0 ;;
 DEC LR9 1 ;;
 {{ imm('LR11',4*(in0_d2+2*padding)*wp-1) }}
clear:
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1 ; INC LR10 1 ; BLT.S LR10 LR11 clear ;;
 SET LR7 CR0 ; SET LR8 CR0 ;;
 {{ imm('LR9',4*(padding*wp+padding)-1) }}
input_y:
 SET LR14 CR0 ; SET LR15 CR0 ; SET LR6 CR0 ;;
input_x:
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; SET LR10 CR0 ; SET LR11 CR0 ; SET LR13 LR3 ;;
 ADD LR13 LR13 LR7 ;;
 LD.MULT R0 LR13 {{ cr.in0 }} ;;
 {{ step('LR13',in0_d2) }}
 {% if oc > 1 and cout%128 %}
 {{ imm('LR4',oc-1) }}
 BEQ LR2 LR4 select_tail ;;
 {% endif %}
 {% macro gather(lanes,label) %}
 {% if lanes > 1 %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD14 LRD10 7 ; LD.MULT R0 LR13 {{ cr.in0 }} ; INC LR13 {{ in0_d2 }} ; ADDBI LRD10 1 ;;
 {% endif %}
 {% if lanes > 2 %}
 {{ imm('LR4',lanes-3) }}
gather_{{ label }}:
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD14 LRD10 7 ; LD.MULT R0 LR13 {{ cr.in0 }} ; INC LR13 {{ in0_d2 }} ; ADDBI LRD10 1 ; DEC LR4 1 ;;
 BLT.S CR0 LR4 gather_{{ label }} ;;
 {% endif %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD14 LRD10 7 ;;
 {% macro repair(c) %}
 SET LR13 LR3 ;;
 ADD LR13 LR13 LR7 ;;
 {% if c == 1 %}{{ step('LR13',in0_d2) }}
 {% elif c %}{{ imm('LR4',c*in0_d2) }} ADD LR13 LR13 LR4 ;;
 {% endif %}
 LD.MULT R0 LR13 {{ cr.in0 }} ;;
 SET LR10 CR0 ; SET LR11 CR0 ;;
 {% if c %}ADDBI LRD10 {{ c }} ;;{% endif %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD14 LRD10 7 ;;
 {% endmacro %}
 {{ repair(0) }}
 {% if lanes > 2 %}{% for c in [1,lanes-2,lanes-1] %}{{ repair(c) }}{% endfor %}{% endif %}
 {% endmacro %}
 {{ gather([128,cout]|min,'full') }}
 {% if oc > 1 and cout%128 %}B gather_end ;;
select_tail:
 {{ gather(cout%128,'tail') }}
gather_end:
 {% endif %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1 ;;
 {% for p in range(3) %}
 LD.MULT R0 LR9 {{ cr.pad }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1 ;;
 {% endfor %}
 ADDBI LRD14 1 ; INC LR6 1 ;;
 {{ imm('LR4',in0_d3) }}
 BLT.S LR6 LR4 input_x ;;
 {{ step('LR9',8*padding) }}
 INC LR7 1 ;;
 {{ imm('LR4',in0_d2) }}
 BLT.S LR7 LR4 input_y ;;
 {# Convolve the channel-major lanes. #}
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR8 LR2 ;;
 DEC LR5 1 ; DEC LR8 {{ oc }} ;;
 {{ imm('LR10',out0_d3) }}
pixel:
 SET LR4 LR5 ; SET LR13 CR0 ;;
 {% if oc > 1 %}SET LR13 LR2 ;{% for i in range(1) %} ;; {% endfor %}
 {{ imm('LR15',2+2*kh*kw) }}
 SET LR13 CR0 ; SET LR11 CR0 ;;
weight_offset:
 BEQ LR11 LR2 weight_ready ;;
 ADD LR13 LR13 LR15 ; INC LR11 1 ; B weight_offset ;;
weight_ready:
 {% endif %}
 DEC LR13 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 {% macro tap(t,last) %}
 {% if t and t % kw == 0 %}ADD LR4 LR4 {{ cr.window_jump }} ;;{% endif %}
 {{ imm('LR11',3) }}
tap_{{ t }}:
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; DEC LR11 1 ; BLT.S CR0 LR11 tap_{{ t }} ;;
 {% if not last %}
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 {% endif %}
 {% endmacro %}
 {% for t in range(kh*kw) %}{{ tap(t,loop.last) }}{% endfor %}
 ACTIVATE.QUANTIZE generic {{ ds }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ 4*stride }} ; INC LR6 1 ;;
 BLT.S LR6 LR10 pixel ;;
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5',4*stride*(wp-out0_d3)) }}
 BLT.S LR7 {{ cr.out0_d2 }} pixel ;;
 INC LR2 1 ;;
 {{ imm('LR4',128*in0_d2) }}
 ADD LR3 LR3 LR4 ;;
 {{ imm('LR4',oc) }}
 BLT.S LR2 LR4 chunk ;;
 HALT ;;
