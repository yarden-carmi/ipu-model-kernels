{# Dense input planes, one independent normalization row per lane. #}
{% set q = cr.qf_in0 ~ '.L' %}
{% set s = cr.stat ~ '.H' %}
{% set w = cr.wide ~ '.L' %}
{% set refine = rows >= 128 %}
{% set mean_q = s if refine else q %}
{% set batched = in0_d0 > 1 %}
{% set blocks = (in0_d1+127)//128 %}
{% set span = channels // in0_d0 %}
{% set phases = namespace(values=[]) %}
{% if batched and span %}
{% for p in range(span) %}
{% set phase = (128*p)%span %}
{% if phase not in phases.values %}{% set phases.values = phases.values + [phase] %}{% endif %}
{% endfor %}
{% endif %}
{% set fast = batched and rows == in0_d0*in0_d1 and channels == in0_d2 and in0_d1 % 128 == 0 and channels % in0_d0 == 0 and span >= 32 and span <= 42 and span * (phases.values|length) <= 350 %}
{% set center_q = w if refine and not fast else s %}
{% set gq = q %}
{% set stride = blocks if batched else (rows+127)//128 %}
{% set half = false %}
{% macro tile_body(label, ds, partial) %}
{% macro loadx(i) %}
 ADD LR12 LR5 LR13 ;; LD.MULT.CYCLIC LR12 {{ cr.tmp }} LR0 ; INC LR5 {{ stride }} ;
 {% if i and half and not partial %};; INC LR12 1 ; LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR2 ;{% endif %}
{% endmacro %}
{% macro store(reg,fmt,fn='identity') %}
 ACTIVATE.QUANTIZE {{ fn }} {{ ds }} {{ fmt }} {{ cr.tmp }} {{ reg }}
{% endmacro %}
{% macro v(reg,fmt,op='ADD',tail='') %}
 MULT.VE {{ reg }} CR1 0 LR0 CR15.L {{ fmt }} ; ACC.{{ op }} {{ tail }} ;;
{% endmacro %}
{% macro rc(reg,src,fmt,op='ADD',tail='') %}
  MULT.RC.{{ 'VE' if src == 'CR1' or src == 'LR0' else 'VV' }} {{ reg }} {{ src }} 0 LR0 CR15.L {{ fmt }} ; ACC.{{ op }} {{ tail }} ;;
{% endmacro %}
{% macro variance(name,fmt) %}
 {% if fast %}
 ADD LR6 LR6 LR6 ;; DEC LR6 2 ;;
 {{ label }}_{{ name }}:
 MULT.RC.VS LR0 0 LR0 CR15.L {{ fmt }} ; ACC.ADD ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {{ rc('LR0','R0',fmt,'ADD','; LD.MULT.CYCLIC LR7 '~cr.tmp~' LR2') }}
 {{ rc('LR0','R0',fmt,'ADD','; INC LR7 1') }}
 MULT.RC.VS LR2 0 LR0 CR15.L {{ fmt }} ; ACC.ADD ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ; DEC LR6 1 ; BNE LR6 CR0 {{ label }}_{{ name }} ;;
 MULT.RC.VS LR0 0 LR0 CR15.L {{ fmt }} ; ACC.ADD ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {{ rc('LR0','R0',fmt,'ADD','; LD.MULT.CYCLIC LR7 '~cr.tmp~' LR2') }}
 {{ rc('LR0','R0',fmt) }}
 MULT.RC.VS LR2 0 LR0 CR15.L {{ fmt }} ; ACC.ADD ; SET LR7 CR0 ;;
 INC LR7 2 ;;
 {% else %}
 ADD LR6 LR6 LR6 ;;
 DEC LR6 2 ;;
 {{ label }}_{{ name }}:
 MULT.RC.VS LR0 0 LR0 CR15.L {{ fmt }} ; ACC.ADD ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ; INC LR7 2 ; DEC LR6 1 ; BNE LR6 CR0 {{ label }}_{{ name }} ;;
 MULT.RC.VS LR0 0 LR0 CR15.L {{ fmt }} ; ACC.ADD ; SET LR7 CR0 ;;
 INC LR7 2 ;;
 {% endif %}
{% endmacro %}
{{ label }}:
 SET LR5 LR3 ; SET LR6 {{ cr.count }} ; SET LR7 CR0 ;;
 {% if fast %}
 ADD LR12 LR5 LR13 ; ADD LR6 LR6 LR6 ; SET LR11 CR1 ; LD.MULT R0 LR0 {{ cr.crow }} ;;
 LD.MULT.CYCLIC LR12 {{ cr.tmp }} LR0 ; DEC LR6 3 ;;
 {{ rc('LR0','LR0',gq,'ADD.FIRST','; INC LR12 '~stride~' ; LD.MULT.CYCLIC LR12 '~cr.tmp~' LR0') }}
 {{ label }}_sum_a:
 {{ rc('LR0','LR0',gq,'ADD','; INC LR12 '~stride~' ; LD.MULT.CYCLIC LR12 '~cr.tmp~' LR0 ; DEC LR6 1 ; BNE LR6 CR0 '~label~'_sum_a') }}
 {{ rc('LR0','LR0',gq) }}
 ADD LR12 LR3 LR13 ; SET LR6 {{ cr.count }} ; LD.MULT R0 LR11 {{ cr.crow }} ;;
 ADD LR6 LR6 LR6 ; LD.MULT.CYCLIC LR12 {{ cr.tmp }} LR0 ;;
 DEC LR6 2 ;;
 {{ label }}_sum_b:
 {{ rc('LR0','LR0',gq,'ADD','; INC LR12 '~stride~' ; LD.MULT.CYCLIC LR12 '~cr.tmp~' LR0 ; DEC LR6 1 ; BNE LR6 CR0 '~label~'_sum_b') }}
 {{ rc('LR0','LR0',gq) }}
 {% else %}
 LD.MULT R0 LR0 {{ cr.crow }} ;; {{ loadx(0) }} ;;
 {% macro sum_pair(part,first=false) %}
 {% for i in range(2) %}
  MULT.RC.VE {{ 'LR1' if half and i else 'LR0' }} LR0 0 LR0 CR15.L {{ gq }} ; ACC.ADD{% if first and i==0 %}.FIRST{% endif %}
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
 {% endif %}
 {# Retain the residual of each quantized mean and centered value. #}
 {{ store('LR0',mean_q) }} ; SET LR5 LR3 ; SET LR6 {{ cr.count }} ; SET LR7 CR0 ;;
 LD.MULT R0 LR0 {{ cr.tmp }} ; INC LR7 1 ;;
 {{ v('LR0',mean_q,'SUB','; '~store('LR7',mean_q)) }}
 {% if refine %}
 LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {{ v('LR0',mean_q,'SUB','; INC LR7 1 ; '~store('LR7',w)) }}
 {% endif %}
 {% if fast %}
 LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR1 ; SET LR11 CR1 ; SET LR4 CR0 ;;
 LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ; INC LR4 2 ; ADD LR12 LR3 LR13 ;;
 LD.MULT R1 LR4 {{ cr.tmp }} ; SET LR7 CR0 ; ADD LR6 LR6 LR6 ;;
 LD.MULT.CYCLIC LR12 {{ cr.tmp }} LR0 ; INC LR7 4 ; DEC LR6 2 ;;
 {{ label }}_center_fast:
 {{ rc('LR0','CR1',gq,'ADD.FIRST') }}
 {{ rc('LR1','CR1',mean_q,'SUB') }}
 {{ rc('LR2','CR1',mean_q,'SUB') }}
 MULT.VE LR2 CR1 0 LR0 CR15.L {{ w }} ; ACC.SUB ; INC LR7 1 ; {{ store('LR7',s) }} ;;
 LD.MULT R0 LR7 {{ cr.tmp }} ; INC LR12 {{ stride }} ;;
 {{ v('LR0',s,'SUB','; INC LR7 1 ; '~store('LR7',s)~' ; LD.MULT.CYCLIC LR12 '~cr.tmp~' LR0 ; DEC LR6 1 ; BNE LR6 CR0 '~label~'_center_fast') }}
 {{ rc('LR0','CR1',gq,'ADD.FIRST') }}
 {{ rc('LR1','CR1',mean_q,'SUB') }}
 {{ rc('LR2','CR1',mean_q,'SUB') }}
 MULT.VE LR2 CR1 0 LR0 CR15.L {{ w }} ; ACC.SUB ; INC LR7 1 ; {{ store('LR7',s) }} ;;
 LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {{ v('LR0',s,'SUB','; INC LR7 1 ; '~store('LR7',s)) }}
 {% else %}
 SET LR7 CR0 ; SET LR11 CR1 ; SET LR4 CR0 ;; INC LR7 5 ; INC LR4 2 ;;
{{ label }}_center:
 {% for i in range(2) %}
 {{ loadx(i) }} ;;
  {% if fast %}
  MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ gq }} ; ACC.ADD.FIRST ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
  {% else %}
  LD.MULT R0 LR0 {{ cr.tmp }} ;;
  {{ rc('LR1' if half and i else 'LR0','CR1',gq,'ADD.FIRST') }}
  {% endif %}
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
 {% endif %}
 SET LR7 CR0 ; SET LR6 {{ cr.count }} ; LD.MULT R0 LR0 {{ cr.epsilon }} ;; INC LR7 5 ;;
 {{ v('LR0',w,'ADD.FIRST','; LD.MULT.CYCLIC LR7 '~cr.tmp~' LR0') }}
 {{ variance('variance',center_q) }}
 {% if refine and not fast %}
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
 {% if fast %}
 {# Refine the rounded reciprocal root using both pieces of the variance. #}
 SET LR10 CR0 ; SET LR11 CR0 ;; INC LR10 3 ; INC LR11 4 ;;
 {{ store('LR7',s,'rsqrt') }} ;;
 {{ store('LR10',s) }} ;; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ v('LR0',s,'SUB','; '~store('LR11',s)) }}
 LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ rc('LR0','R0',s,'ADD.FIRST','; LD.MULT R0 LR11 '~cr.tmp) }}
 {{ rc('LR0','R0',s,'ADD','; '~store('LR10',s)) }}
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ v('LR0',s,'SUB','; '~store('LR11',s)) }}
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ rc('LR0','R0',s,'SUB.FIRST','; LD.MULT R0 LR11 '~cr.tmp) }}
 {{ rc('LR0','R0',s,'SUB','; LD.MULT R0 LR7 '~cr.tmp) }}
 {# -vy² + 1, with 1 and 1/2 supplied alongside epsilon. #}
 SET LR10 CR1 ;; LD.MULT R0 LR10 {{ cr.epsilon }} ;;
 {{ v('LR0',s,'ADD','; '~store('LR11',s)) }}
 LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.epsilon }} ;;
 {{ rc('LR2','R0',s,'ADD.FIRST','; '~store('LR11',s)) }}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 {{ rc('LR0','R0',s,'ADD.FIRST') }}
 {{ rc('LR0','CR1',s,'ADD','; '~store('LR7',s)) }}
 LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {{ v('LR0',s,'SUB','; '~store('LR11',s)) }}
 SET LR8 LR3 ; SET LR9 CR0 ;;
 LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR1 ;;
 {% else %}
 {{ store('LR7',s,'rsqrt') }} ; SET LR8 LR3 ; SET LR9 CR0 ;;
 {% endif %}
 LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
 INC LR10 3 ; INC LR11 4 ; INC LR7 3 ;;
 SET LR6 {{ cr.count }} ; ADD LR4 LR2 LR2 ;;
 ADD LR6 LR6 LR6 ;;
{{ label }}_affine:
 LD.MULT R0 LR9 {{ cr.gamma }} ;;
 {{ rc('LR0','R0',s,'ADD.FIRST','; INC LR9 1 ; LD.MULT R0 LR9 '~cr.gamma) }}
 {% if fast %}{{ rc('LR1','R0',s,'ADD','; DEC LR9 1 ; LD.MULT R0 LR9 '~cr.gamma) }}
 {{ rc('LR1','R0',s,'ADD','; INC LR9 1 ; LD.MULT R0 LR9 '~cr.gamma) }}{% endif %}
 {{ rc('LR0','R0',s,'ADD','; '~store('LR10',s)) }}
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ v('LR0',s,'SUB','; '~store('LR11',s)~' ; LD.MULT.CYCLIC LR7 '~cr.tmp~' LR2') }}
 {{ rc('LR2','R0',s,'ADD.FIRST','; LD.MULT.CYCLIC LR7 '~cr.tmp~' LR4 ; INC LR7 1') }}
 {{ rc('LR4','R0',s,'ADD','; LD.MULT R0 LR11 '~cr.tmp) }}
 {{ rc('LR2','R0',s,'ADD','; LD.MULT R0 LR9 '~cr.beta~' ; DEC LR9 1') }}
 {{ v('LR0',q,'ADD','; LD.MULT R0 LR9 '~cr.beta~' ; INC LR9 1 ; INC LR7 1 ; DEC LR6 1') }}
 {{ v('LR0',q,'ADD','; ACTIVATE.QUANTIZE '~(act_out0|default('identity'))~' '~ds~' '~cr.qf_out0~'.L '~cr.out0~' LR8 ; INC LR9 1') }}
 INC LR8 {{ stride }} ; BNE LR6 CR0 {{ label }}_affine ;;
{% endmacro %}
{% macro incn(reg,n) %}
{% for i in range((n+126)//127) %}INC {{ reg }} {{ [127,n-127*i]|min }} ;;{% endfor %}
{% endmacro %}
{% if fast %}
 {# A 128-token segment stays inside one input lane block. Gather the
    3 or 4 tokens from each physical channel with one packed reshape. #}
 SET LR5 LR0 ; SET LR7 LR1 ; SET LR10 CR0 ;;
 SET LR8 CR0 ; SET LR9 CR0 ; SET LR12 LR2 ;;
 SET LR15 {{ cr.count }} ; SET LR11 CR0 ;;
 ADD LR15 LR15 LR15 ;; ADD LR15 LR15 LR15 ;; INC LR15 5 ;;
 ADD LR4 LR4 LR15 ; SET LR6 LR15 ; DEC LR15 1 ;;
g_batch:
 {{ incn('LR6',channels*blocks) }}
 {% for phase in phases.values %}
g_phase_{{ phase }}:
 SET LR0 CR0 ; SET LR1 LR5 ; SET LR14 LR9 ;;
 ADDB LRD0 LR11 ; SET LR2 CR0 ; SET LR3 LR7 ;;
 {% if phase*in0_d0*blocks > 255 %}{{ incn('LR14',phase*in0_d0*blocks) }}{% endif %}
 {% if 0 < phase*in0_d0*blocks <= 255 %}INC LR14 {{ phase*in0_d0*blocks }} ; {% endif %}LD.MULT R0 LR14 {{ cr.in0 }} ;;
 {% macro taps(first,last) %}
 {% for j in range(first,last) %}
 {% if j %}ADDBI LRD2 1 ; {% endif %}
 {% if phase and j == span-phase %}ADDBI LRD0 1 ; {% endif %}
 MULT.VE LR10 CR1 0 LR10 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 {{ 4 if j < 128%span else 5 }} ;
 {% if j == span-1 %}
 ACTIVATE.QUANTIZE identity CR15.L {{ gq }} {{ cr.tmp }} LR15 ; INC LR11 {{ (phase+128)//span }} ; INC LR15 1 ;
 {% else %}
 {% if j+1 == span-phase %}SET LR14 LR9 ; {% else %}INC LR14 {{ in0_d0*blocks }} ; {% endif %}LD.MULT R0 LR14 {{ cr.in0 }} ;
 {% endif %} ;;
 {% endfor %}
 {% endmacro %}
 {{ taps(0,[span,32]|min) }}{{ taps(32,span) }}
 {% endfor %}
 INC LR15 1 ;; BEQ LR15 LR6 g_next_batch ;;
 SET LR14 CR0 ;; INC LR14 128 ;;
 DEC LR15 1 ; BLT.S LR11 LR14 g_phase_0 ;;
 SET LR11 CR0 ; INC LR9 1 ; DEC LR12 1 ;;
 BNE LR12 CR0 g_phase_0 ;;
 SET LR12 CR0 ;;
 {{ incn('LR12',blocks) }}
 {{ incn('LR9',(channels-1)*blocks) }}
 B g_phase_0 ;;
g_next_batch:
 BEQ LR15 LR4 g_ready ;;
 INC LR8 {{ blocks }} ; SET LR11 CR0 ; DEC LR15 1 ;;
 SET LR9 LR8 ; SET LR12 CR0 ;;
 {{ incn('LR12',blocks) }}
 B g_batch ;;
g_ready:
{% else %}
 {# Reorder the recorded flat-storage view into channel planes. #}
 {% macro gather(name,limit,ds) %}
 SET LR11 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
 {{ name }}_element:
 MULT.EE LR5 CR1 0 LR0 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR4 {{ stride }} ; INC LR7 1 ; INC LR11 1 ;;
 ADDBI LRD2 1 ; BNE LR7 LR12 {{ name }}_nowrap ;;
 SET LR7 CR0 ; INC LR5 1 ;; BLT.S LR5 LR15 {{ name }}_sameblock ;;
 SET LR5 CR0 ; INC LR6 1 ;;
 {{ name }}_sameblock:
 SET LR4 LR6 ;;
 {{ name }}_nowrap:
 LD.MULT R0 LR4 {{ cr.in0 }} ; BLT.S LR11 {{ limit }} {{ name }}_element ;;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR8 ;; INC LR8 1 ;;
 {% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR8 {{ cr.count }} ; SET LR9 CR0 ; SET LR12 CR0 ;;
 ADD LR8 LR8 LR8 ;; ADD LR8 LR8 LR8 ;; INC LR8 5 ;; SET LR13 LR8 ;;
 {% for i in range((in0_d2 + 126) // 127) %}INC LR12 {{ [127, in0_d2 - i * 127] | min }} ;;{% endfor %}
 SET LR14 {{ cr.count }} ; SET LR15 CR0 ;;
 ADD LR14 LR14 LR14 ; INC LR15 128 ;;
 gather_channel:
 SET LR10 CR0 ;;
 {% if rows >= 128 %}
 gather_tile:
 {{ gather('full_gather','LR15','CR15.L') }}
 INC LR10 1 ;; BLT.S LR10 {{ cr.tiles }} gather_tile ;;
 {% endif %}
 {% if rows % 128 %}
 SET LR10 CR0 ;; INC LR10 {{ rows % 128 }} ;;
 {{ gather('tail_gather','LR10',cr.wide~'.H') }}
 {% endif %}
 INC LR9 1 ;; BLT.S LR9 LR14 gather_channel ;;
{% endif %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 {{ 128 if fast else 64 }} ; INC LR2 128 ; SET LR3 CR0 ;;
 {% if fast %}ADD LR1 LR1 LR2 ;; ADD LR1 LR1 LR2 ;;{% endif %}
 {% if fast %}
 SET LR13 {{ cr.count }} ; SET LR15 CR0 ;;
 ADD LR13 LR13 LR13 ;; ADD LR13 LR13 LR13 ;; INC LR13 5 ;;
 {{ incn('LR15',in0_d0) }}
 norm_batch:
 SET LR14 CR0 ;;
 {{ incn('LR14',blocks) }}
 {{ tile_body('tile',cr.stat~'.L',false) }}
 INC LR3 1 ; DEC LR14 1 ;;
 BNE LR14 CR0 tile ;;
 DEC LR15 1 ;; BEQ LR15 CR0 norm_done ;;
 {{ incn('LR3',(channels-1)*blocks) }}
 B norm_batch ;;
 norm_done:
 {% elif rows >= 128 %}
 {{ tile_body('tile',cr.stat~'.L',false) }}
 INC LR3 1 ;;
  BLT.S LR3 {{ cr.tiles }} tile ;;
 {% endif %}
 {% if not fast and rows % 128 %}{{ tile_body('tail',cr.wide~'.H',true) }}{% endif %}
 HALT ;;
