{# Dense input planes, one independent normalization row per lane. #}
{% set q = cr.qf_in0 ~ '.L' %}
{% set s = cr.stat ~ '.H' %}
{% set w = cr.wide ~ '.L' %}
{% set refine = rows >= 128 %}
{% set center_q = w if refine else s %}
{% set mean_q = s if refine else q %}
{% set stride = (rows+127)//128 %}
{% set half = rows%128 != 0 %}
{% macro tile_body(label, ds, partial) %}
{% macro loadx(i) %}
 SET LR12 LR5 ; LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR0 ; {% if rows//128 + (i if half else 0) %}INC LR5 {{ rows//128 + (i if half else 0) }} ; {% endif %}
 {% if i and half and not partial %};; INC LR12 1 ; LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR2 ;{% endif %}
{% endmacro %}
{% macro store(reg,fmt,fn='identity') %}
 ACTIVATE.QUANTIZE {{ fn }} {{ ds }} {{ fmt }} {{ cr.tmp }} {{ reg }}
{% endmacro %}
{% macro v(reg,fmt,op='ADD',tail='') %}
 MULT.VE {{ reg }} CR1 0 LR0 CR15.L {{ fmt }} ; ACC.{{ op }} {{ tail }} ;;
{% endmacro %}
{% macro rc(reg,src,fmt,op='ADD',tail='') %}
 MULT.RC.{{ 'VE' if src == 'CR1' else 'VV' }} {{ reg }} {{ src }} 0 LR0 CR15.L {{ fmt }} ; ACC.{{ op }} {{ tail }} ;;
{% endmacro %}
{% macro variance(name,fmt) %}
 ADD LR6 LR6 LR6 ;;
 DEC LR6 2 ;;
 {{ label }}_{{ name }}:
 MULT.RC.VS LR0 0 LR0 CR15.L {{ fmt }} ; ACC.ADD ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ; INC LR7 2 ; DEC LR6 1 ; BNE LR6 CR0 {{ label }}_{{ name }} ;;
 MULT.RC.VS LR0 0 LR0 CR15.L {{ fmt }} ; ACC.ADD ; SET LR7 CR0 ;;
 INC LR7 2 ;;
{% endmacro %}
{{ label }}:
 SET LR5 LR3 ; SET LR6 {{ cr.count }} ; SET LR7 CR0 ;;
 LD.MULT R0 LR0 {{ cr.crow }} ;; {{ loadx(0) }} ;;
 {% macro sum_pair(part,first=false) %}
 {% for i in range(2) %}
 MULT.RC.VE {{ 'LR1' if half and i else 'LR0' }} LR0 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if first and i==0 %}.FIRST{% endif %}
 {% if i==0 %}; {{ loadx(1) }}{% elif not first %}; BNE LR6 CR0 {{ label }}_sum{{ part }}_next{% endif %} ;;
 {% endfor %}
 {% endmacro %}
 {{ sum_pair(0,true) }}
 DEC LR6 1 ; BNE LR6 CR0 {{ label }}_sum0_next ;;
 B {{ label }}_sum0_end ;;
 {% for p in range(2) %}
 {% if p %}SET LR5 LR3 ; SET LR6 {{ cr.count }} ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.crow }} ;;{% endif %}
 {{ label }}_sum{{ p }}_next:
 DEC LR6 1 ; {{ loadx(0) }} ;;
 {{ sum_pair(p) }}
 {{ label }}_sum{{ p }}_end:
 {% endfor %}
 {# Retain the residual of each quantized mean and centered value. #}
 {{ store('LR0',mean_q) }} ; SET LR5 LR3 ; SET LR6 {{ cr.count }} ; SET LR7 CR0 ;;
 LD.MULT R0 LR0 {{ cr.tmp }} ; INC LR7 1 ;;
 {{ v('LR0',mean_q,'SUB','; '~store('LR7',mean_q)) }}
 {% if refine %}
 LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {{ v('LR0',mean_q,'SUB','; INC LR7 1 ; '~store('LR7',w)) }}
 {% endif %}
 SET LR7 CR0 ; SET LR11 CR1 ; SET LR4 CR0 ;; INC LR7 5 ; INC LR4 2 ;;
{{ label }}_center:
 {% for i in range(2) %}
 {{ loadx(i) }} ;;
 LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {{ rc('LR1' if half and i else 'LR0','CR1',q,'ADD.FIRST') }}
 {{ v('LR0',mean_q,'SUB','; LD.MULT R0 LR11 '~cr.tmp) }}
 {% if refine %}
 {{ v('LR0',mean_q,'SUB','; LD.MULT R0 LR4 '~cr.tmp) }}
 {{ v('LR0',w,'SUB','; '~store('LR7',center_q)) }}
 {% else %}
 {{ v('LR0',mean_q,'SUB','; '~store('LR7',center_q)) }}
 {% endif %}
 LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {{ v('LR0',center_q,'SUB','; INC LR7 1 ; '~store('LR7',center_q)) }}
 INC LR7 1 ; {% if i==1 %}DEC LR6 1 ;{% endif %} ;;
 {% endfor %}
 BNE LR6 CR0 {{ label }}_center ;;
 SET LR7 CR0 ; SET LR6 {{ cr.count }} ; LD.MULT R0 LR0 {{ cr.epsilon }} ;; INC LR7 5 ;;
 {{ v('LR0',w,'ADD.FIRST','; LD.MULT.CYCLIC LR7 '~cr.tmp~' LR0') }}
 {{ variance('variance',center_q) }}
 {% if refine %}
 {# Rescale before switching to fixed point so tiny rows are retained. #}
 {{ store('LR7',w,'rsqrt') }} ; SET LR10 CR0 ; SET LR6 {{ cr.count }} ;;
 LD.MULT R1 LR7 {{ cr.tmp }} ; INC LR10 4 ;;
 ADD LR6 LR6 LR6 ; INC LR7 3 ;;
 {{ label }}_refine_center:
 LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
 {{ rc('LR0','R1',w,'ADD.FIRST','; INC LR7 1 ; LD.MULT.CYCLIC LR7 '~cr.tmp~' LR0') }}
 DEC LR7 1 ; MULT.RC.VV LR0 R1 0 LR0 CR15.L {{ w }} ; ACC.ADD ; {{ store('LR7',s) }} ;;
 LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {{ v('LR0',s,'SUB','; INC LR7 1 ; DEC LR6 1 ; '~store('LR7',s)) }}
 INC LR7 1 ; BNE LR6 CR0 {{ label }}_refine_center ;;
 SET LR7 CR0 ;; INC LR7 2 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR2 ;;
 MULT.RC.VS LR2 0 LR0 CR15.L {{ w }} ; ACC.ADD.FIRST ; {{ store('LR10',w) }} ;;
 LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR0 {{ cr.epsilon }} ; SET LR7 CR0 ;;
 {{ rc('LR0','R0',w,'ADD.FIRST','; INC LR7 5 ; LD.MULT.CYCLIC LR7 '~cr.tmp~' LR0 ; SET LR6 '~cr.count) }}
 {{ variance('corrected',s) }}
 {% endif %}
 {{ store('LR7',s,'rsqrt') }} ; SET LR8 LR3 ; SET LR9 CR0 ;;
 LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
 INC LR10 3 ; INC LR11 4 ; INC LR7 3 ;;
 SET LR6 {{ cr.count }} ; ADD LR4 LR2 LR2 ; DEC LR8 {{ stride }} ;;
 ADD LR6 LR6 LR6 ;;
{{ label }}_affine:
 LD.MULT R0 LR9 {{ cr.gamma }} ;;
 {{ rc('LR0','R0',s,'ADD.FIRST','; INC LR9 1 ; LD.MULT R0 LR9 '~cr.gamma) }}
 {{ rc('LR0','R0',s,'ADD','; '~store('LR10',s)) }}
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ v('LR0',s,'SUB','; '~store('LR11',s)~' ; LD.MULT.CYCLIC LR7 '~cr.tmp~' LR2') }}
 {{ rc('LR2','R0',s,'ADD.FIRST','; LD.MULT.CYCLIC LR7 '~cr.tmp~' LR4 ; INC LR7 1') }}
 {{ rc('LR4','R0',s,'ADD','; LD.MULT R0 LR11 '~cr.tmp) }}
 {{ rc('LR2','R0',s,'ADD','; LD.MULT R0 LR9 '~cr.beta~' ; DEC LR9 1') }}
 {{ v('LR0',q,'ADD','; LD.MULT R0 LR9 '~cr.beta~' ; INC LR9 1 ; INC LR7 1 ; DEC LR6 1') }}
 {{ v('LR0',q,'ADD','; ACTIVATE.QUANTIZE '~(act_out0|default('identity'))~' '~ds~' '~cr.qf_out0~'.L '~cr.out0~' LR8 ; INC LR8 '~stride~' ; INC LR9 1 ; BNE LR6 CR0 '~label~'_affine') }}
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 64 ; INC LR2 128 ; SET LR3 CR0 ;;
 {% if rows >= 128 %}
 {{ tile_body('tile',cr.stat~'.L',false) }}
 INC LR3 1 ;;
 BLT.S LR3 {{ cr.tiles }} tile ;;
 {% endif %}
 {% if half %}{{ tile_body('tail',cr.wide~'.H',true) }}{% endif %}
 HALT ;;
