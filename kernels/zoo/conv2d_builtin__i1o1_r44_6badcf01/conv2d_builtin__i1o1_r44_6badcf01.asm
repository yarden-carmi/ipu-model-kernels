{% macro step(r,n) %}
{% for k in range(0,n|abs,255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255,(n|abs)-k]|min }} ;;
{% endfor %}
{% endmacro %}

{% if cin == 32 and w % 4 == 0 and stride == 1 %}
{# Four adjacent input pixels per row. Each VV instruction covers all
   96 weights of one filter row for one output channel. #}
{% macro dot(dest) -%}
 MULT.RC.VV LR8 R0 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM {{ dest }} {{ cr.full }}.H
{%- endmacro %}
 SET LR7 CR0 ; SET LR15 CR0 ; DEC LR2 1 ;;
 INC LR7 128 ; INC LR15 192 ;;
 INC LR15 192 ;;
 batch:
 SET LR0 CR0 ;;
 y:
 SET LR1 CR0 ; SET LR14 CR0 ;;
 pixel:
 SET LR4 CR0 ; SET LR11 LR0 ; SET LR12 LR3 ;;
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR9 ; INC LR4 1 ; DEC LR11 1 ; SUB LR12 LR12 {{ cr.y_end }} ;;
 MULT.RC.VE LR9 CR1 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR9 ; INC LR4 1 ;;
 MULT.RC.VE LR9 CR1 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
 tap_row:
 BLT.S LR11 CR0 skip_row ;;
 BGE.S LR11 {{ cr.h }} skip_row ;;
 SET LR8 CR0 ; LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR9 ;;
 BEQ LR14 CR0 previous ;;
 BEQ LR14 CR1 row_ready ;;
 INC LR8 32 ; BEQ LR14 {{ cr.blocks }} row_ready ;;
 INC LR8 32 ; SET LR13 LR12 ;;
 INC LR13 1 ; BEQ LR1 {{ cr.x_end }} zero_next ;;
 LD.MULT.CYCLIC LR13 {{ cr.in0 }} LR7 ; BEQ LR9 CR0 row_ready ;;
 zero_next:
 LD.MULT.CYCLIC LR9 {{ cr.weights }} LR7 ; BEQ LR9 CR0 row_ready ;;
 previous:
 DEC LR8 32 ; SET LR13 LR12 ;;
 DEC LR13 1 ; BEQ LR1 CR0 zero_prev ;;
 LD.MULT.CYCLIC LR13 {{ cr.in0 }} LR15 ; BEQ LR9 CR0 row_ready ;;
 zero_prev:
 LD.MULT.CYCLIC LR9 {{ cr.weights }} LR15 ;;
 row_ready:
 SET LR5 CR0 ; SET LR6 CR0 ;;
 LD.MULT R0 LR4 {{ cr.weights }} ; INC LR4 1 ; DEC LR5 1 ;;
{% if cout > 1 %}
 filter:
 {{ dot('LR6') }} ; LD.MULT R0 LR4 {{ cr.weights }} ; INC LR4 1 ; INC LR5 1 ;;
 {{ dot('LR5') }} ; LD.MULT R0 LR4 {{ cr.weights }} ; INC LR4 1 ; INC LR6 1 ; BLT.S LR6 {{ cr.panel_end }} filter ;;
{% endif %}
 {{ dot('LR6') }} ; LD.MULT R0 LR4 {{ cr.weights }} ; INC LR4 1 ; INC LR5 1 ;;
 {{ dot('LR5') }} ; BEQ LR9 CR0 next_row ;;
 skip_row:
 ADD LR4 LR4 {{ cr.tap_rows }} ;;
 next_row:
 INC LR11 1 ; ADD LR12 LR12 {{ cr.y_end }} ;;
 BLT.S LR11 LR0 tap_row ;;
 BEQ LR11 LR0 tap_row ;;
 SET LR13 LR0 ;;
 INC LR13 1 ;;
 BEQ LR11 LR13 tap_row ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ; INC LR1 1 ; INC.MODP2 LR14 CR1 2 ;;
 BNE LR14 CR0 same_input_row ;;
 INC LR3 1 ;;
 same_input_row:
 BLT.S LR1 {{ cr.w }} pixel ;;
 INC LR0 1 ;;
 BLT.S LR0 {{ cr.h }} y ;;
 DEC LR10 1 ;;
 BLT.S CR0 LR10 batch ;;
 HALT ;;
{% else %}
{% macro prime() %}
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
{% endmacro %}
{% macro accumulate(src, first='ACC.ADD', more=false, advance='') %}
 MULT.RC.VE LR15 {{ src }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ first }} ; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; INC LR4 1 ;;
 MULT.RC.VE LR15 {{ src }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 {% if more %}; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15{% endif %}{% if advance %} ; INC {{ advance }} 2{% endif %} ;;
{% endmacro %}
{% macro channel_pair(i, more=true) %}
 {{ accumulate('LR11' if i % 2 == 0 else 'LR12', more=more, advance=('LR12' if i % 2 == 0 else 'LR11') if more else '') }}
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
 ADD LR9 LR14 LR6 ; SET LR11 CR0 ; SET LR12 CR0 ;;
 LD.MULT R0 LR9 {{ cr.in0 }} ; DEC LR12 1 ;;
 {{ prime() }}
{% if cin > 16 %}
 channel:
{% for i in range(16) %}
 {{ channel_pair(i) }}
{% endfor %}
 BLT.S LR11 {{ cr.panel_end }} channel ;;
{% endif %}
{% for i in range((cin - 1) % 16) %}
 {{ channel_pair(i) }}
{% endfor %}
 {{ channel_pair(cin - 1, false) }}
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
{% endif %}
