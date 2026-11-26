{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% macro term(slot, weight, first=false) %}
 MULT.RC.VE {{slot}} {{weight}} 0 LR0 {{cr.valid}}.L {{cr.qf_in0}}.L ; ACC.ADD{{'.FIRST' if first else ''}} ;;
{% endmacro %}
{% macro blend(c,v,h,d) %}
 {{term(d,w1,true)}}
 {{term(h,w3)}}
 {{term(v,w3)}}
 {{term(c,w9)}}
 ACTIVATE.QUANTIZE identity {{cr.valid}}.L {{cr.qf_out0}}.L {{cr.tmp}} LR4 ;;
 LD.MULT R0 LR4 {{cr.tmp}} ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.valid}}.L {{cr.qf_out0}}.L ; ACC.SUB ;;
 INC LR4 1 ;;
 ACTIVATE.QUANTIZE identity {{cr.valid}}.L {{cr.qf_out0}}.L {{cr.tmp}} LR4 ;;
 INC LR4 1 ;;
{% endmacro %}
{% macro load_columns(c,v) %}
 LD.MULT.CYCLIC LR7 {{cr.in0}} {{c}} ;;
 LD.MULT.CYCLIC LR8 {{cr.in0}} {{v}} ;;
{% endmacro %}
{% macro step(c,v,h,d,edge,next) %}
 INC LR7 1 ; INC LR8 1 ; INC LR9 1 ;;
 BGE.S LR9 {{cr.in0_d3}} {{edge}} ;;
 {{load_columns(h,d)}}
 {{blend(c,v,h,d)}}
 {{blend(h,d,c,v)}}
 {% if next %}BEQ CR0 CR0 {{next}} ;;{% endif %}
{% endmacro %}
{% macro scan(side) %}
 SET LR7 LR5 ; SET LR8 LR6 ; SET LR9 CR0 ;;
 {{load_columns('LR0','LR1')}}
 {{blend('LR0','LR1','LR0','LR1')}}
a_{{side}}:
 {{step('LR0','LR1','LR2','LR3','edge_a_'~side,'')}}
 {{step('LR2','LR3','LR0','LR1','edge_b_'~side,'a_'~side)}}
edge_a_{{side}}:
 {{blend('LR0','LR1','LR0','LR1')}}
 BEQ CR0 CR0 end_{{side}} ;;
edge_b_{{side}}:
 {{blend('LR2','LR3','LR2','LR3')}}
end_{{side}}:
{% endmacro %}
 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 SET LR10 CR0 ; SET LR1 CR0 ;;
 INC LR1 128 ;;
 ADD LR2 LR1 LR1 ;;
 ADD LR3 LR2 LR1 ;;
y:
 SUB LR6 LR5 {{cr.in0_d3}} ; BNE LR10 CR0 above ;;
 SET LR6 LR5 ;;
above:
 {{scan('above')}}
 INC LR10 1 ; ADD LR6 LR5 {{cr.in0_d3}} ;;
 BLT.S LR10 {{cr.in0_d2}} below ;;
 SET LR6 LR5 ;;
below:
 {{scan('below')}}
 ADD LR5 LR5 {{cr.in0_d3}} ; BLT.S LR10 {{cr.in0_d2}} y ;;
 {% macro setnum(reg, n) %}
 SET {{reg}} CR0 ;;
 {% if n >= 16384 %}INC {{reg}} {{n // 16384}} ;;{% for i in range(7) %}ADD {{reg}} {{reg}} {{reg}} ;;{% endfor %}{% endif %}
 {% if n >= 128 %}{% if (n // 128) % 128 %}INC {{reg}} {{(n // 128) % 128}} ;;{% endif %}{% for i in range(7) %}ADD {{reg}} {{reg}} {{reg}} ;;{% endfor %}{% endif %}
 {% if n % 128 %}INC {{reg}} {{n % 128}} ;;{% endif %}
 {% endmacro %}
 {% macro gather_digit(digit) %}
 SET LR10 LR6 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 {% if digit %}INC LR10 1 ;;{% endif %}
 SET LR7 CR0 ;;
gather_{{digit}}:
 LD.MULT R0 LR10 {{cr.tmp}} ;;
 MULT.EE LR4 CR1 0 LR0 {{cr.valid}}.L {{cr.qf_out0}}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
 ADDBI LRD2 1 ; INC LR10 2 ; INC LR7 1 ;;
 BLT.S LR7 LR14 gather_{{digit}} ;;
 ACTIVATE.QUANTIZE identity {{cr.valid}}.L {{cr.qf_out0}}.L {{cr.tmp}} LR12 ;;
 {% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
 SET LR5 CR0 ; SET LR6 CR0 ;;
 {{setnum('LR12', 2 * oh * ow)}}
 {{setnum('LR13', channels)}}
 {{setnum('LR14', 128)}}
 {{setnum('LR15', oh * ow)}}
channel:
 SET LR6 CR0 ; SET LR11 CR0 ;;
line:
 {{gather_digit(0)}}
 INC LR12 1 ;;
 {{gather_digit(1)}}
 DEC LR12 1 ;;
 LD.MULT.CYCLIC LR12 {{cr.tmp}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{cr.valid}}.L {{cr.qf_out0}}.L ; ACC.ADD.FIRST ;;
 INC LR12 1 ;;
 LD.MULT.CYCLIC LR12 {{cr.tmp}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{cr.valid}}.L {{cr.qf_out0}}.L ; ACC.ADD ;;
 DEC LR12 1 ;;
 ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.valid}}.L {{cr.qf_out0}}.L {{cr.out0}} LR5 ;;
 INC LR5 1 ; INC LR11 128 ; SET LR6 LR10 ;;
 DEC LR6 1 ;;
 BLT.S LR11 LR15 line ;;
 INC LR4 1 ;;
 BLT.S LR4 LR13 channel ;;
 HALT ;;
