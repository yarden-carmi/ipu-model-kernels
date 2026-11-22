{% macro step(r,n) %}
{% for k in range(0,n|abs,255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255,(n|abs)-k]|min }} ;;
{% endfor %}
{% endmacro %}
{# Folded rows are bias, then (ky, kx, input channel), each with two parts. #}
{# The multiplier reads slot zero before the load replaces it. #}
{% macro prime() %}
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
{% endmacro %}
{% macro accumulate(src, first='ACC.ADD', more=false) %}
 MULT.RC.VE LR15 {{ src }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ first }} ; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; INC LR4 1 ;;
 MULT.RC.VE LR15 {{ src }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 {% if more %}; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15{% endif %} ;;
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
 {{ step('LR14',-padding*w-padding) }}
ky:
 SET LR6 CR0 ;;
kx:
 ADD LR7 LR0 LR5 ; ADD LR8 LR2 LR6 ;;
 DEC LR7 {{ padding }} ; DEC LR8 {{ padding }} ;;
 BLT.S LR7 CR0 skip ;;
 BGE.S LR7 {{ cr.h }} skip ;;
 BLT.S LR8 CR0 skip ;;
 BGE.S LR8 {{ cr.w }} skip ;;
 ADD LR9 LR14 LR6 ; SET LR11 CR0 ;;
 LD.MULT R0 LR9 {{ cr.in0 }} ;;
 {{ prime() }}
{% if cin > 1 %}
channel:
 {{ accumulate('LR11', more=true) }}
 INC LR11 1 ; BLT.S LR11 {{ cr.last_prefetch }} channel ;;
{% endif %}
 {# The final pair doesn't load past the tap, including at the end of weights. #}
 {{ accumulate('LR11') }}
 BEQ LR15 CR0 next ;;
skip:
 ADD LR4 LR4 {{ cr.tap_rows }} ;;
next:
 INC LR6 1 ; SET LR7 CR0 ;;
 INC LR7 {{ kw }} ;;
 BLT.S LR6 LR7 kx ;;
 INC LR5 1 ; ADD LR14 LR14 {{ cr.w }} ; SET LR7 CR0 ;;
 INC LR7 {{ kh }} ;;
 BLT.S LR5 LR7 ky ;;
 INC LR3 1 ;;
{% if cout > 128 %}
 BGE.S LR3 {{ cr.blocks }} last_block ;;
 {{ store(cr.full) }}
 BEQ LR15 CR0 block ;;
last_block:
{% endif %}
 {{ store(cr.tail) }}
 INC LR1 {{ stride }} ; INC LR2 {{ stride }} ;;
 BLT.S LR2 {{ cr.x_end }} ox ;;
 {{ step('LR1', stride*w-((w+2*padding-kw)//stride+1)*stride) }}
 INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.y_end }} oy ;;
 {{ step('LR1', (h-((h+2*padding-kh)//stride+1)*stride)*w) }}
 DEC LR10 1 ;;
 BLT.S CR0 LR10 batch ;;
 HALT ;;
