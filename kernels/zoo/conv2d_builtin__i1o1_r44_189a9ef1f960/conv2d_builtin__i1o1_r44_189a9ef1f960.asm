{% macro step(r,n) %}
{% for k in range(0,n|abs,255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255,(n|abs)-k]|min }} ;;
{% endfor %}
{% endmacro %}
{# Adapted from the channel-lane 189a9ef1f960 variant. #}
{# The multiplier reads slot zero before the load replaces it. #}
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
{% if pack == 4 or dot %}
{# LR3 is the cyclic window offset; LR6 is the destination channel. #}
{% macro dot_pair(first, last) %}
 INC LR4 1 {% if not first %}; INC LR6 1{% endif %} ; LD.MULT R0 LR4 {{ cr.weights }} ; MULT.RC.VV LR3 R0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ cr.full }}.L ;;
 INC LR4 1 ; MULT.RC.VV LR3 R0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ cr.full }}.L {% if not last %}; LD.MULT R0 LR4 {{ cr.weights }}{% endif %} ;;
{% endmacro %}
 SET LR15 CR0 ; SET LR13 CR0 ; SET LR1 CR0 ;;
 SET LR12 CR0 ; SET LR11 CR0 ;;
 INC LR11 2 ;;
 {{ step('LR12',pitch) }}
{% if pack == 4 %}
 SET LR14 CR0 ;;
 INC LR14 128 ;;
{% endif %}
dot_batch:
 SET LR0 CR0 ;;
dot_y:
 SET LR2 CR0 ; SET LR8 CR0 ; SET LR3 CR0 ;;
{% if pack == 4 %}
 DEC LR8 1 ; INC LR3 96 ;;
{% endif %}
dot_x:
 SET LR4 CR0 ; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 {{ accumulate('CR1', 'ACC.ADD.FIRST') }}
 SET LR4 LR11 ; SET LR5 CR0 ; SUB LR9 LR1 LR12 ;;
 ADD LR9 LR9 LR8 {% if pack == 4 %}; INC LR4 1{% endif %} ;;
{% if pack == 1 %}
 DEC LR9 1 ;;
{% endif %}
dot_ky:
 ADD LR7 LR0 LR5 ;;
 DEC LR7 1 ;;
 BLT.S LR7 CR0 dot_skip_y ;;
 BGE.S LR7 {{ cr.in0_d2 }} dot_skip_y ;;
{% if pack == 4 %}
 BLT.S LR8 CR0 dot_left_zero ;;
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR15 ; BEQ LR15 CR0 dot_left_done ;;
dot_left_zero:
 LD.MULT.CYCLIC LR11 {{ cr.weights }} LR15 ;;
dot_left_done:
 ADD LR7 LR8 CR0 ; INC LR9 1 ;;
 INC LR7 1 ;;
 BGE.S LR7 LR12 dot_right_zero ;;
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR14 ; BEQ LR15 CR0 dot_right_done ;;
dot_right_zero:
 LD.MULT.CYCLIC LR11 {{ cr.weights }} LR14 ;;
dot_right_done:
 DEC LR9 1 ;;
{% else %}
 SET LR14 CR0 ;;
dot_kx:
 ADD LR7 LR2 LR14 ;;
 DEC LR7 1 ;;
 BLT.S LR7 CR0 dot_skip_x ;;
 BGE.S LR7 {{ cr.in0_d3 }} dot_skip_x ;;
 ADD LR7 LR9 LR14 ; LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR15 ;;
{% endif %}
 SET LR6 CR0 ; LD.MULT R0 LR4 {{ cr.weights }} ;;
{% for i in range(out0_d1) %}
 {{ dot_pair(i == 0, i == out0_d1 - 1) }}
{% endfor %}
{% if pack == 1 %}
 BEQ LR15 CR0 dot_next_x ;;
dot_skip_x:
 {{ step('LR4',2*out0_d1) }}
dot_next_x:
 INC LR14 1 ; SET LR7 CR0 ;;
 INC LR7 {{ kw }} ;;
 BLT.S LR14 LR7 dot_kx ;;
{% endif %}
 BEQ LR15 CR0 dot_next_y ;;
dot_skip_y:
 {{ step('LR4',2*out0_d1*(1 if pack == 4 else kw)) }}
dot_next_y:
 INC LR5 1 ; ADD LR9 LR9 LR12 ; SET LR7 CR0 ;;
 INC LR7 {{ kh }} {% if pack == 4 %}; SET LR6 CR0{% endif %} ;;
 BLT.S LR5 LR7 dot_ky ;;
 {{ store(cr.tail) }}
{% if pack == 4 %}
 INC LR6 32 ;;
 INC LR2 1 ; INC.MODP2 LR3 LR6 7 ;;
 BNE LR3 CR0 dot_x_advance ;;
 INC LR8 1 ;;
dot_x_advance:
{% else %}
 INC LR2 {{ stride }} ; INC LR8 {{ stride }} ;;
{% endif %}
 BLT.S LR2 {{ cr.x_end }} dot_x ;;
 INC LR0 {{ stride }} ; ADD LR1 LR1 LR12 ;;
{% if stride == 2 %}
 ADD LR1 LR1 LR12 ;;
{% endif %}
 BLT.S LR0 {{ cr.y_end }} dot_y ;;
 {{ step('LR1',(in0_d2-out0_d2*stride)*pitch) }}
 DEC LR10 1 ;;
 BLT.S CR0 LR10 dot_batch ;;
 HALT ;;
{% else %}
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
 {{ step('LR14',-padding*in0_d3-padding) }}
ky:
 SET LR6 CR0 ;;
kx:
 ADD LR7 LR0 LR5 ; ADD LR8 LR2 LR6 ;;
 DEC LR7 {{ padding }} ; DEC LR8 {{ padding }} ;;
 BLT.S LR7 CR0 skip ; ADD LR9 LR14 LR6 ;;
 BGE.S LR7 {{ cr.in0_d2 }} skip ; SET LR11 CR0 ;;
 BLT.S LR8 CR0 skip ; SET LR12 CR0 ;;
 BGE.S LR8 {{ cr.in0_d3 }} skip ;;
 LD.MULT R0 LR9 {{ cr.in0 }} ; DEC LR12 1 ;;
 {{ prime() }}
 {# Advance the inactive channel counter during the residual multiply. #}
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
{% endif %}
