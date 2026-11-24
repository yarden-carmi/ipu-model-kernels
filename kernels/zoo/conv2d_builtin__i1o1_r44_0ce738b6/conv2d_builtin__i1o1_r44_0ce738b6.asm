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
{% if channels == 64 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% macro band(tag, index, ds) %}
 SUB LR8 LR9 CR1 ; INC LR6 1 ; LD.MULT R0 LR6 {{ cr.weights }} ;;
 {% if outputs > 16 %}
 {{ tag }}_panel:
 {% for i in range(16) %}{{ mac(index, ds) }}{% endfor %}
 BLT.S LR8 {{ cr.oc_end }} {{ tag }}_panel ;;
 {% endif %}
 {% for i in range((outputs - 1) % 16 + 1) %}{{ mac(index, ds, loop.last) }}{% endfor %}
{% endmacro %}
{% macro mac(index, ds, last=false) %}
 LD.MULT R0 LR6 {{ cr.weights }} ; MULT.RC.VV {{ index }} R0 0 LR9 {{ ds }}.L {{ qi }} ; AGG.SUM LR8 {{ ds }}.L ; INC LR8 1 ; INC LR6 1 ;;
 MULT.RC.VV {{ index }} R0 0 LR9 {{ ds }}.L {{ qi }} ; AGG.SUM LR8 {{ ds }}.L {% if not last %}; LD.MULT R0 LR6 {{ cr.weights }} ; INC LR6 1{% endif %} ;;
{% endmacro %}
{# Stage only the two right-hand half-rows whose weights share one segment. #}
{% macro right(tag, dy) %}
 {% if dy < 0 %}BEQ LR0 CR0 {{ tag }}_zero ;;{% endif %}
 BGE.S LR1 {{ cr.column_limit }} {{ tag }}_zero ; SET LR5 LR2 ;;
 {% if dy < 0 %}DEC LR5 {{ pw }} ;;{% endif %}
 BLT.S LR3 CR0 {{ tag }}_load ;;
 INC LR5 1 ;;
 {{ tag }}_load:
 LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR11 ; BEQ LR9 CR0 {{ tag }}_copy ;;
 {{ tag }}_zero:
 LD.MULT.CYCLIC LR9 {{ cr.weights }} LR11 ;;
 {{ tag }}_copy:
 MULT.RC.VE LR14 CR1 0 LR9 {{ full }} {{ qi }} ; ACC.STRIDE 64 off on {{ 'LR9' if dy < 0 else 'LR15' }} {% if dy == 0 %}; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.pack_or_pair }} LR9{% endif %} ;;
{% endmacro %}
 SET LR2 CR0 ; SET LR9 CR0 ; SET LR11 CR0 ;;
 SET LR12 CR0 ; SET LR13 CR0 ; INC LR11 128 ;;
 DEC LR13 1 ; {{ inc('LR12', 384) }}
 batch64:
 SET LR0 CR0 ;;
 y64:
 SET LR1 CR0 ; SET LR7 CR0 ; SET LR3 CR0 ;;
 DEC LR3 64 ;;
 x64:
 SUB LR14 LR11 LR3 ; SET LR15 CR0 ;;
 INC LR15 2 ;;
 {{ right('upper', -1) }}
 {{ right('middle', 0) }}
 SET LR6 CR0 ; SET LR4 LR2 ; SET LR5 LR0 ;;
 LD.MULT.CYCLIC LR6 {{ cr.weights }} LR9 ; INC LR6 1 ; DEC LR5 1 ;;
 MULT.RC.VE LR9 CR1 0 LR9 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR6 {{ cr.weights }} LR9 ; INC LR6 1 ;;
 MULT.RC.VE LR9 CR1 0 LR9 {{ full }} {{ qi }} ; ACC.ADD ; DEC LR4 {{ pw }} ;;
 ky64:
 BLT.S LR5 CR0 skip64 ;;
 BGE.S LR5 {{ cr.in0_d2 }} skip64 ;;
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR9 ; BGE.S LR3 CR0 wide64 ; SUB LR15 LR4 CR1 ;;
 BEQ LR7 CR0 first64 ;;
 LD.MULT.CYCLIC LR15 {{ cr.in0 }} LR12 ; BEQ LR9 CR0 wide64 ;;
 first64:
 LD.MULT.CYCLIC LR9 {{ cr.weights }} LR12 ;;
 wide64:
 {{ band('wide', 'LR3', cr.full) }}
 BEQ LR9 CR0 next64 ;;
 skip64:
 ADD LR6 LR6 {{ cr.tap_rows }} ;;
 next64:
 ADD LR15 LR0 CR1 ;;
 INC LR5 1 ; INC LR4 {{ pw }} ; BLT.S LR5 LR15 ky64 ;;
 # The loop compares before advancing; LR4 now addresses the row after the window.
 LD.MULT.CYCLIC LR9 {{ cr.pack_or_pair }} LR9 ;;
 {{ band('pair', 'LR9', cr.full) }}
 ADD LR15 LR0 CR1 ;;
 BGE.S LR15 {{ cr.in0_d2 }} store64 ;;
 DEC LR4 {{ pw }} ;;
 BGE.S LR1 {{ cr.column_limit }} lastzero64 ;;
 BLT.S LR3 CR0 lastload64 ;;
 INC LR4 1 ;;
 lastload64:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR11 ; BEQ LR9 CR0 lastdot64 ;;
 lastzero64:
 LD.MULT.CYCLIC LR9 {{ cr.weights }} LR11 ;;
 lastdot64:
 {{ band('last', 'LR14', cr.last) }}
 store64:
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ; INC LR13 1 ; INC LR1 {{ stride }} ;;
 BGE.S LR1 {{ cr.in0_d3 }} next_row64 ; INC LR3 {{ 64 * stride }} ;;
 BLT.S LR3 CR1 x64 ;;
 DEC LR3 128 ; INC LR2 1 ; INC LR7 1 ; BEQ LR9 CR0 x64 ;;
 next_row64:
 SUB LR2 LR2 LR7 ; INC LR0 {{ stride }} ;;
 {{ inc('LR2', pw * stride) }}
 BLT.S LR0 {{ cr.in0_d2 }} y64 ;;
 {% if in0_d2 % stride %}DEC LR2 {{ pw }} ;;{% endif %}
 DEC LR10 1 ;;
 BLT.S CR0 LR10 batch64 ;;
 HALT ;;
{% elif channels == 32 %}
{% macro dot32(last=false) %}
 MULT.RC.VV LR3 R0 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR8 {{ cr.last }}.L ; INC LR8 1 ; INC LR6 1 ; LD.MULT R0 LR6 {{ cr.weights }} ;;
 MULT.RC.VV LR3 R0 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR8 {{ cr.last }}.L {% if last %}; DEC LR5 1 ; INC LR4 {{ pw }} ; BLT.S CR0 LR5 ky32{% else %}; INC LR6 1 ; LD.MULT R0 LR6 {{ cr.weights }}{% endif %} ;;
{% endmacro %}
 SET LR2 CR0 ; SET LR9 CR0 ; SET LR11 CR0 ;;
 SET LR12 CR0 ; SUB LR13 LR9 CR1 ; INC LR11 128 ;;
 {{ inc('LR12', 384) }}
 batch32:
 SET LR0 CR0 ;;
 y32:
 SET LR1 CR0 ; SET LR7 CR0 ; SUB LR3 LR9 CR1 ;;
 DEC LR3 31 ;;
 x32:
 SET LR6 CR0 ; SET LR4 LR2 ; SET LR5 CR1 ;;
 LD.MULT.CYCLIC LR6 {{ cr.weights }} LR9 ; INC LR6 1 ; ADD LR8 LR0 CR1 ; BEQ LR0 CR0 bias32 ;;
 INC LR5 1 ; DEC LR4 {{ pw }} ;;
 bias32:
 MULT.RC.VE LR9 CR1 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR6 {{ cr.weights }} LR9 ; INC LR6 1 ; BGE.S LR8 {{ cr.in0_d2 }} bottom32 ;;
 bias_low32:
 MULT.RC.VE LR9 CR1 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; BEQ LR0 CR0 top_weights32 ;;
 ky32:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR9 ; SUB LR14 LR4 CR1 ; ADD LR15 LR4 CR1 ; BEQ LR7 CR0 left32 ;;
 LD.MULT.CYCLIC LR14 {{ cr.in0 }} LR12 ; BGE.S LR7 {{ cr.column_limit }} right32 ;;
 LD.MULT.CYCLIC LR15 {{ cr.in0 }} LR11 ;;
 dots32:
 SUB LR8 LR9 CR1 ; INC LR6 1 ; LD.MULT R0 LR6 {{ cr.weights }} ;;
 {% if outputs > panel %}
 oc32:
 {% for i in range(panel) %}{{ dot32() }}{% endfor %}
 BLT.S LR8 {{ cr.oc_end }} oc32 ;;
 {% endif %}
 {% for i in range((outputs - 1) % panel + 1) %}{{ dot32(loop.last) }}{% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ; INC LR13 1 ; INC LR1 {{ stride }} ; INC LR3 {{ 32 * stride }} ;;
 BGE.S LR1 {{ cr.in0_d3 }} end_y32 ;;
 BLT.S LR3 {{ cr.pack_or_pair }} x32 ;;
 DEC LR3 128 ; INC LR2 1 ; INC LR7 1 ; BEQ LR9 CR0 x32 ;;
 end_y32:
 SUB LR2 LR2 LR7 ; INC LR0 {{ stride }} ;;
 {{ inc('LR2', pw * stride) }}
 BLT.S LR0 {{ cr.in0_d2 }} y32 ;;
 {% if in0_d2 % stride %}DEC LR2 {{ pw }} ;;{% endif %}
 DEC LR10 1 ;;
 BLT.S CR0 LR10 batch32 ;;
 HALT ;;
 bottom32:
 DEC LR5 1 ; BEQ LR9 CR0 bias_low32 ;;
 top_weights32:
 ADD LR6 LR6 {{ cr.tap_rows }} ; BEQ LR9 CR0 ky32 ;;
 left32:
 LD.MULT.CYCLIC LR9 {{ cr.weights }} LR12 ; BGE.S LR7 {{ cr.column_limit }} right32 ;;
 LD.MULT.CYCLIC LR15 {{ cr.in0 }} LR11 ; BEQ LR9 CR0 dots32 ;;
 right32:
 LD.MULT.CYCLIC LR9 {{ cr.weights }} LR11 ; BEQ LR9 CR0 dots32 ;;
{% else %}
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
 BGE.S LR7 {{ cr.column_limit }} right_zero ; ADD LR14 LR4 CR1 ;;
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
 BLT.S LR3 {{ cr.pack_or_pair }} x ;;
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
{% endif %}
