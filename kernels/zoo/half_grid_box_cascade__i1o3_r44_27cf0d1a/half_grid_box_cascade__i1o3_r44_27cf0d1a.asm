{% macro term(slot, weight, first=false) %}
 MULT.RC.VE {{ slot }} {{ weight }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
{% macro blend(c,v,h,d) %}
 {% if format == 'fp32' %}
 {{ term(d, cr.f1, true) }}
 {% for i in range(3) %}{{ term(h, cr.f1) }}{% endfor %}
 {% for i in range(3) %}{{ term(v, cr.f1) }}{% endfor %}
 {% for i in range(9) %}{{ term(c, cr.f1) }}{% endfor %}
 {% else %}
 {{ term(d, cr.w1, true) }}
 {{ term(h, cr.w3) }}
 {{ term(v, cr.w3) }}
 {{ term(c, cr.w9) }}
 {% endif %}
 ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR4 ;;
 LD.MULT R0 LR4 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.residual }} LR4 ;;
 LD.MULT.CYCLIC LR14 {{ cr.in0 }} LR0 ;;
 INC LR4 1 ;;
{% endmacro %}
{% macro load(c,v) %}
 {% if c == 'LR0' %}SET LR14 LR7 ;;{% endif %}
 LD.MULT.CYCLIC LR7 {{ cr.in0 }} {{ c }} ;;
 LD.MULT.CYCLIC LR8 {{ cr.in0 }} {{ v }} ;;
{% endmacro %}
{% macro step(c,v,h,d,edge,next) %}
 INC LR7 1 ; INC LR8 1 ; INC LR9 1 ;;
 BGE.S LR9 {{ cr.in0_d3 }} {{ edge }} ;;
 {{ load(h,d) }}
 {{ blend(c,v,h,d) }}
 {{ blend(h,d,c,v) }}
 {% if next %}B {{ next }} ;;{% endif %}
{% endmacro %}
{% macro scan(side) %}
 SET LR7 LR5 ; SET LR8 LR6 ; SET LR9 CR0 ;;
 {{ load('LR0','LR1') }}
 {{ blend('LR0','LR1','LR0','LR1') }}
a_{{side}}:
 {{ step('LR0','LR1','LR2','LR3','edge_a_'~side,'') }}
 {{ step('LR2','LR3','LR0','LR1','edge_b_'~side,'a_'~side) }}
edge_a_{{side}}:
 {{ blend('LR0','LR1','LR0','LR1') }}
 B end_{{side}} ;;
edge_b_{{side}}:
 {{ blend('LR2','LR3','LR2','LR3') }}
end_{{side}}:
{% endmacro %}
 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 SET LR10 CR0 ; SET LR1 CR0 ;;
 INC LR1 128 ;;
 ADD LR2 LR1 LR1 ;;
 ADD LR3 LR2 LR1 ;;
y:
 SUB LR6 LR5 {{ cr.in0_d3 }} ; BNE LR10 CR0 above ;;
 SET LR6 LR5 ;;
above:
 {{ scan('above') }}
 INC LR10 1 ; ADD LR6 LR5 {{ cr.in0_d3 }} ;;
 BLT.S LR10 {{ lr.in0_d2 }} below ;;
 SET LR6 LR5 ;;
below:
 {{ scan('below') }}
 ADD LR5 LR5 {{ cr.in0_d3 }} ; BLT.S LR10 {{ lr.in0_d2 }} y ;;
 SET LR8 CR0 ; SET LR4 CR0 ;;
channel:
 SET LR10 CR0 ; SET LR14 CR0 ;;
rowpair:
 SET LR5 CR0 ;;
gather_start:
 SET LR6 LR10 ; SET LR0 CR0 ; SET LR1 CR0 ;;
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR7 CR0 ;;
 SET LR9 CR0 ;;
 MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
gather:
 BNE LR5 CR0 residual_load ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 B loaded ;;
residual_load:
 LD.MULT R0 LR6 {{ cr.residual }} ;;
loaded:
 MULT.EE LR4 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
 ADDBI LRD2 1 ; INC LR6 1 ; INC LR7 1 ;;
 BLT.S LR7 {{ cr.out0_d3 }} gather ;;
 INC LR9 1 ;;
 BNE LR9 CR1 save ;;
 SET LR7 CR0 ;;
 B gather ;;
save:
 BNE LR5 CR0 combine ;;
 ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.residual }} LR11 ;;
 INC LR5 1 ;;
 B gather_start ;;
combine:
 LD.MULT R0 LR11 {{ cr.residual }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
 INC LR8 1 ; INC LR14 2 ; ADD LR10 LR10 {{ cr.out0_d3 }} ;;
 ADD LR10 LR10 {{ cr.out0_d3 }} ; BLT.S LR14 {{ lr.out0_d2 }} rowpair ;;
 SET LR1 CR0 ;;
 INC LR1 127 ;;
 MULT.EE LR1 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity {{ cr.full }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
 INC LR8 1 ; INC LR4 1 ;;
 BLT.S LR4 LR15 channel ;;
 HALT ;;
