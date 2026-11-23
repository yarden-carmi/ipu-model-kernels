{% if cin == cout and cin == groups %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{# The MULT reads R0 before the same word replaces it with the next part. #}
{% macro next_weight() %}LD.MULT R0 LR4 {{ cr.weights }} ; INC LR4 1{% endmacro %}
{% macro scalar_parts(scalar, first=false) %}
 {{ next_weight() }} ;;
 {% for p in range(3) %}
 MULT.VE LR0 {{ scalar }} 0 LR0 {{ full }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if first and p == 0 else 'ACC.ADD' }} {% if p < 2 %}; {{ next_weight() }}{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro tap(x) %}
 {% if stride == 2 and x != 0 %}
 ADD LR14 LR8 LR11 ;;
 {% else %}
 SET LR14 LR8 ;;
 {% endif %}
 {% if x == -1 %}DEC LR14 1 ;;{% endif %}
 {% if stride == 1 and x == 1 %}INC LR14 1 ;;{% endif %}
 {% if x == -1 %}{{ next_weight() }} ;;{% endif %}
 {% for p in range(3) %}
 MULT.RC.VV LR14 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD {% if x != 1 or p < 2 %}; {{ next_weight() }}{% endif %} ;;
 {% endfor %}
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 SET LR11 CR0 ; SET LR12 CR0 ;;
 INC LR11 128 ; INC LR12 255 ;;
 INC LR12 1 ;;
{% if stride == 2 %}
 {# Decimate each input row once, into its even and odd columns. #}
 {% macro decimate(odd) %}
 MULT.RC.VE {{ 'LR9' if odd else 'LR11' }} CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 {% if out0_d3 > 32 %}
 MULT.RC.VE {{ 'LR10' if odd else 'LR8' }} CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ;;
 {% endif %}
 ACTIVATE.QUANTIZE identity {{ cr.decimated }}.L {{ qi }} {{ cr.parity }} LR3 ;;
 INC LR3 1 ;;
 {% endmacro %}
 SET LR8 LR11 ; SET LR9 LR11 ; SET LR10 LR11 ;;
 INC LR8 64 ; INC LR9 1 ; INC LR10 65 ;;
stage_row:
 LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR11 ;;
 {{ decimate(false) }}
 {{ decimate(true) }}
 INC LR2 1 ;;
 BLT.S LR2 LR7 stage_row ;;
 SET LR2 CR0 ; SET LR3 CR0 ;;
{% endif %}

 SET LR1 LR5 ;;
 SET LR5 CR0 ;;
channel:
 SET LR13 CR0 ;;
batch:
 SET LR6 CR0 ;;
 packed_row:
 SET LR4 LR5 ; SET LR7 CR0 ; SET LR8 LR11 ;;
 {# LD.MULT sees the incremented pointer, so start one row before the block. #}
 DEC LR4 1 ;;
 {{ scalar_parts('CR1', true) }}
 BEQ LR0 CR0 vertical_start ;;
slot:
 {{ scalar_parts('CR1') }}
vertical_start:
 SET LR9 LR6 ; SET LR10 LR2 ; SET LR15 LR6 ;;
 DEC LR9 1 ; DEC LR10 {{ stride }} ; INC LR15 2 ;;
vertical:
 BLT.S LR9 CR0 zero_taps ;;
 BGE.S LR9 {{ cr.in0_d2 }} zero_taps ;;
 {% if stride == 2 %}
 LD.MULT.CYCLIC LR10 {{ cr.parity }} LR11 ; SET LR14 LR10 ;;
 INC LR14 1 ;;
 LD.MULT.CYCLIC LR14 {{ cr.parity }} LR12 ;;
 {% else %}
 LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR11 ;;
 {% endif %}
 {% for x in [-1, 0, 1] %}{{ tap(x) }}{% endfor %}
 BEQ LR0 CR0 vertical_next ;;
 zero_taps:
 {# Consume the folded rows for vertical padding without accumulating them. #}
 {% for k in range(9) %}
 {{ next_weight() }} ;;
 {% endfor %}
vertical_next:
 INC LR9 1 ; INC LR10 {{ stride }} ;;
 BLT.S LR9 LR15 vertical ;;
 INC LR6 {{ stride }} ; INC LR2 {{ stride * stride }} ; INC LR7 1 ;;
 SUB LR8 LR8 {{ cr.out0_d3 }} ;;
 BLT.S LR7 {{ cr.pack }} slot ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.packed }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
 INC LR3 1 ;;
 BLT.S LR6 {{ cr.in0_d2 }} packed_row ;;
 {% if stride == 2 and in0_d2 % 2 == 1 %}DEC LR2 2 ;;{% endif %}
 INC LR13 1 ;;
 BLT.S LR13 {{ cr.in0_d0 }} batch ;;
 ADD LR5 LR5 {{ cr.weight_span }} ;;
 BLT.S LR5 LR1 channel ;;
{% endif %}
 HALT ;;
