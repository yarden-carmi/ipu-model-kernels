{% macro step(r,n) %}
{% for k in range(0,n|abs,255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255,(n|abs)-k]|min }} ;;
{% endfor %}
{% endmacro %}
{# The multiplier consumes slot zero before the bundled load replaces it. #}
{% macro prime() %}
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
{% endmacro %}
{% macro accumulate(src, first='ACC.ADD', more=false, advance='') %}
 MULT.RC.VE LR15 {{ src }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ first }} ; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; INC LR4 1 ;;
 MULT.RC.VE LR15 {{ src }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 {% if more %}; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; INC {{ advance }} 2{% endif %} ;;
{% endmacro %}
{% macro channel_pair(i, more=true) %}
 {{ accumulate('LR11' if i % 2 == 0 else 'LR12', more=more, advance='LR12' if i % 2 == 0 else 'LR11') }}
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 INC LR13 1 ;;
{% endmacro %}

 SET LR15 CR0 ; SET LR13 CR0 ; SET LR1 CR0 ;;
batch:
 SET LR0 CR0 ;;
oy:
 SET LR2 CR0 ;;
ox:
 SET LR3 CR0 ; SET LR4 CR0 ;;
block:
 {{ prime() }}
 {{ accumulate('CR1', 'ACC.ADD.FIRST') }}
 SET LR5 CR0 ; SET LR14 LR1 ;;
 {{ step('LR14',-in0_d3-1) }}
ky:
 SET LR6 CR0 ;;
kx:
 ADD LR7 LR0 LR5 ; ADD LR8 LR2 LR6 ;;
 DEC LR7 1 ; DEC LR8 1 ;;
 BLT.S LR7 CR0 skip ; ADD LR9 LR14 LR6 ;;
 BGE.S LR7 {{ cr.in0_d2 }} skip ; SET LR11 CR0 ;;
 BLT.S LR8 CR0 skip ; SET LR12 CR0 ;;
 BGE.S LR8 {{ cr.in0_d3 }} skip ;;
 LD.MULT R0 LR9 {{ cr.in0 }} ; DEC LR12 1 ;;
 {{ prime() }}
{% if in0_d1 > 16 %}
channel:
{% for i in range(16) %}
 {{ channel_pair(i) }}
{% endfor %}
 BLT.S LR11 {{ cr.panel_end }} channel ;;
{% endif %}
{% for i in range((in0_d1 - 1) % 16) %}
 {{ channel_pair(i) }}
{% endfor %}
 {{ channel_pair(in0_d1 - 1, false) }}
 BEQ LR15 CR0 next ;;
skip:
 ADD LR4 LR4 {{ cr.tap_rows }} ;;
next:
 SET LR7 CR0 ;;
 INC LR7 {{ kw - 1 }} ;;
 INC LR6 1 ; BLT.S LR6 LR7 kx ;;
 SET LR7 CR0 ;;
 INC LR7 {{ kh - 1 }} ;;
 INC LR5 1 ; ADD LR14 LR14 {{ cr.in0_d3 }} ; BLT.S LR5 LR7 ky ;;
{% if out0_d1 > 128 %}
 INC LR3 1 ;;
 BGE.S LR3 {{ cr.blocks }} last_block ;;
 {{ store(cr.full) }}
 BEQ LR15 CR0 block ;;
last_block:
{% endif %}
 {{ store(cr.tail) }}
 INC LR1 {{ stride }} ; INC LR2 {{ stride }} ;;
 BLT.S LR2 {{ cr.x_end }} ox ;;
 {{ step('LR1', stride*(in0_d3-out0_d3)) }}
 INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.y_end }} oy ;;
 {{ step('LR1', (in0_d2-out0_d2*stride)*in0_d3) }}
 DEC LR10 1 ;;
 BLT.S CR0 LR10 batch ;;
 HALT ;;
