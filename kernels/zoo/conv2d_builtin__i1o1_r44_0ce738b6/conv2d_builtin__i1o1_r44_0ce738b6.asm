{% set channels = in0_d1 %}
{% set outputs = out0_d1 %}
{% set segments = (3 * channels + 127) // 128 %}
{% set pack = 128 // channels %}
{% set pw = in0_d3 // pack %}
{% set panel = 32 %}
{% macro inc(reg, amount) %}
{% for i in range(0, amount, 255) %}
 INC {{ reg }} {{ [amount-i, 255]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro advance_y() %}
{% if segments < 3 %}
 INC LR5 1 ; INC LR4 {{ pw }} ; BLT.S LR5 LR15 ky ;;
{% else %}
 INC LR5 1 ; INC LR4 {{ pw }} ; ADD LR14 LR0 CR1 ;;
 INC LR14 1 ;;
 BLT.S LR5 LR14 ky ;;
{% endif %}
{% endmacro %}
{% macro dot(last=false) %}
{% for s in range(segments) %}
{% for part in range(2) %}
 MULT.RC.VV {{ ['LR3', 'LR14', 'LR15'][s] }} R0 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR8 {{ cr.last if s == segments-1 else cr.full }}.L {% if not (last and s == segments-1 and part == 1) %}; INC LR6 1 ; LD.MULT R0 LR6 {{ cr.weights }}{% endif %}{% if s == 0 and part == 0 %}; INC LR8 1{% endif %} ;;
{% endfor %}
{% endfor %}
{% endmacro %}

 SET LR2 CR0 ; SET LR9 CR0 ; SET LR11 CR0 ;;
 SET LR12 CR0 ; SET LR13 CR0 ; INC LR11 128 ;;
 DEC LR13 1 ;;
 {{ inc('LR12', 384) }}
batch:
 SET LR0 CR0 ;;
y:
 SET LR1 CR0 ; SET LR7 CR0 ; SET LR3 CR0 ;;
 {% if segments < 3 %}
 ADD LR15 LR0 CR1 ;;
 {% endif %}
 DEC LR3 {{ channels }} ;;
x:
 SET LR6 CR0 ; SET LR4 LR2 ; SET LR5 LR0 ;;
 LD.MULT.CYCLIC LR6 {{ cr.weights }} LR9 ; INC LR6 1 ; DEC LR5 1 ;;
 MULT.RC.VE LR9 CR1 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR6 {{ cr.weights }} LR9 ; INC LR6 1 ;;
 MULT.RC.VE LR9 CR1 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR4 {{ pw }} ;;
ky:
 BLT.S LR5 CR0 skip_y ;;
 BGE.S LR5 {{ cr.in0_d2 }} skip_y ;;
 # The cyclic input window starts at the left neighbor, possibly in the preceding packed row.
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR9 ; SET LR14 LR4 ;;
 BEQ LR7 CR0 left_zero ;;
 DEC LR14 1 ; LD.MULT.CYCLIC LR14 {{ cr.in0 }} LR12 ;;
 BEQ LR9 CR0 right ;;
left_zero:
 LD.MULT.CYCLIC LR9 {{ cr.weights }} LR12 ;;
right:
 BGE.S LR7 {{ cr.last_packed_column }} right_zero ; ADD LR14 LR4 CR1 ;;
 LD.MULT.CYCLIC LR14 {{ cr.in0 }} LR11 ;;
 BEQ LR9 CR0 dots ;;
right_zero:
 LD.MULT.CYCLIC LR9 {{ cr.weights }} LR11 ;;
dots:
 ADD LR14 LR3 LR11 ; SET LR8 CR0 ;;
 {% if segments == 3 %}ADD LR15 LR14 LR11 ; {% endif %}DEC LR8 1 ; INC LR6 1 ; LD.MULT R0 LR6 {{ cr.weights }} ;;
 {% if outputs > panel %}
oc:
 {% for i in range(panel) %}
 {{ dot() }}
 {% endfor %}
 BLT.S LR8 {{ cr.oc_end }} oc ;;
 {% endif %}
 {% for i in range((outputs - 1) % panel + 1) %}
 {{ dot(loop.last) }}
 {% endfor %}
 BEQ LR9 CR0 next_y ;;
skip_y:
 ADD LR6 LR6 {{ cr.tap_rows }} ;;
next_y:
 {{ advance_y() }}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ; INC LR13 1 ; INC LR1 {{ stride }} ;;
 BGE.S LR1 {{ cr.in0_d3 }} next_row ;;
 {% if pack > 1 %}
 INC LR3 {{ channels * stride }} ;;
 BLT.S LR3 {{ cr.phase_end }} x ;;
 DEC LR3 128 ;;
 {% endif %}
 INC LR2 {{ stride if pack == 1 else 1 }} ; INC LR7 {{ stride if pack == 1 else 1 }} ;;
 BEQ LR9 CR0 x ;;
next_row:
 SUB LR2 LR2 LR7 ; INC LR0 {{ stride }} ;;
 {{ inc('LR2', pw * stride) }}
 BLT.S LR0 {{ cr.in0_d2 }} y ;;
 {% if in0_d2 % stride %}
 DEC LR2 {{ pw }} ;;
 {% endif %}
 DEC LR10 1 ;;
 BLT.S CR0 LR10 batch ;;
 HALT ;;
