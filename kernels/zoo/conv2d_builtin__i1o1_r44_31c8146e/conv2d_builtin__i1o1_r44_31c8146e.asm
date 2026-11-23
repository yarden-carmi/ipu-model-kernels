{% macro step(r,n) %}
{% for k in range(0,n|abs,255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255,(n|abs)-k]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro prime(extra='') %}
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 {{ extra }} ;;
{% endmacro %}
{% macro accumulate(src, first='ACC.ADD', more=false, advance='', branch='', updates='') %}
 MULT.RC.VE LR15 {{ src }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ first }} ; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; INC LR4 1 ;;
 MULT.RC.VE LR15 {{ src }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 {% if more %}; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; INC {{ advance }} 2{% endif %} {{ updates }}{% if branch %} ; {{ branch }}{% endif %} ;;
{% endmacro %}
{% macro channel(i, more=true, branch='', updates='') %}
 {{ accumulate('LR11' if i % 2 == 0 else 'LR12', more=more, advance='LR12' if i % 2 == 0 else 'LR11', branch=branch, updates=updates) }}
{% endmacro %}
{% macro tap(k, branch='', updates='') %}
 LD.MULT R0 LR9 {{ cr.in0 }} ; INC LR9 1 ; SET LR11 CR0 ; SET LR12 CR0 ;;
 {{ prime('; DEC LR12 1') }}
 {% if cin > 16 %}
 channels{{ k }}:
 {% for i in range(16) %}
 {{ channel(i, branch=('BLT.S LR11 LR5 channels' ~ k) if i == 15 else '') }}
 {% endfor %}
 {% endif %}
 {% for i in range((cin - 1) % 16) %}
 {{ channel(i) }}
 {% endfor %}
 {{ channel(cin - 1, false, branch, updates) }}
{% endmacro %}
{% macro store(ds, updates='') %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ; INC LR13 1 {{ updates }} ;;
{% endmacro %}

 SET LR15 CR0 ; SET LR13 CR0 ; SET LR1 CR0 ;;
 DEC LR13 1 ;;
{% if cin > 16 %}
 SET LR5 CR0 ;;
 INC LR5 {{((cin - 1) // 16) * 16 - 2}} ;;
{% endif %}
batch:
 SET LR0 CR0 ;;
oy:
 SET LR2 CR0 ; SET LR6 LR0 ;;
 INC LR6 1 ;;
 BLT.S LR6 {{ cr.h }} ox ;;
 DEC LR6 1 ;;
ox:
 SET LR4 CR0 {% if cout > 128 %}; SET LR3 CR0{% endif %} ;;
block:
 {{ prime() }}
 {{ accumulate('CR1', 'ACC.ADD.FIRST') }}
 SUB LR14 LR1 {{ cr.w }} ; SET LR8 LR2 ; SET LR7 LR0 ;;
 INC LR8 1 ; DEC LR7 1 ; DEC LR14 2 ; BEQ LR0 CR0 skip_top ;;
ky:
 SET LR9 LR14 ; BEQ LR2 CR0 skip_left ;;
 {{ tap(0) }}
center:
 {{ tap(1, 'BGE.S LR8 ' ~ cr.w ~ ' skip_right') }}
 {{ tap(2, 'BLT.S LR7 LR6 ky', '; INC LR7 1 ; ADD LR14 LR14 ' ~ cr.w) }}
finish:
{% if cout > 128 %}
 INC LR3 1 ;;
 BGE.S LR3 {{ cr.blocks }} last_block ;;
 {{ store(cr.full) }}
 BEQ LR15 CR0 block ;;
last_block:
{% endif %}
 {{ store(cr.tail, '; INC LR1 ' ~ stride ~ ' ; INC LR2 ' ~ stride) }}
 BLT.S LR2 {{ cr.x_end }} ox ;;
 {{ step('LR1', stride*w-out0_d3*stride) }}
 INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.y_end }} oy ;;
 {{ step('LR1', (h-out0_d2*stride)*w) }}
 DEC LR10 1 ;;
 BLT.S CR0 LR10 batch ;;
 HALT ;;
skip_top:
 ADD LR4 LR4 {{ cr.tap_rows }} ;;
 ADD LR4 LR4 {{ cr.tap_rows }} ;;
 ADD LR4 LR4 {{ cr.tap_rows }} ; INC LR7 1 ; ADD LR14 LR14 {{ cr.w }} ; BEQ LR15 CR0 ky ;;
skip_right:
 ADD LR4 LR4 {{ cr.tap_rows }} ; INC LR7 1 ; ADD LR14 LR14 {{ cr.w }} ; BLT.S LR7 LR6 ky ;;
 BEQ LR15 CR0 finish ;;
skip_left:
 ADD LR4 LR4 {{ cr.tap_rows }} ; INC LR9 1 ; BEQ LR15 CR0 center ;;
