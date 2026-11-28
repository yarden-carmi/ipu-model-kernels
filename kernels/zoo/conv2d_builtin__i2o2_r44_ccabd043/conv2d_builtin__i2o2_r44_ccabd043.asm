{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set icg = cin // groups %}
{% set ocg = cout // groups %}
{% macro zero_window() %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 {% for x in range(3) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.windows }} LR7 ; INC LR7 1 ;;
 {% endfor %}
{% endmacro %}
{% macro stage_tap(x) %}
 {% set idx = ['LR1', 'LR2', 'LR3'][x] %}
 {% if x == 2 and in0_d2 == 1 %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 {% else %}
 MULT.RC.VE {{ idx }} CR1 0 LR0 {{ ds }} {{ qi }} ;
 {{ 'ACC.STRIDE 64 on off LR0' if stride == 2 else 'ACC.ADD.FIRST' }} ;
 {% endif %}
 ACTIVATE.QUANTIZE identity {{ cr.right if x == 2 else cr.width }}.L {{ qi }} {{ cr.windows }} LR7 ; INC LR7 1 ;;
{% endmacro %}
{% macro digits(index, first=false, bias=false, next_tap=false) %}
 LD.MULT R0 LR12 {{ cr.weights }} ; INC LR12 1 ;;
 {% if bias %} MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ;
 {% else %} MULT.RC.VV {{ index }} R0 0 LR0 {{ ds }} {{ qi }} ; {% endif %}
 {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }} ; LD.MULT R1 LR12 {{ cr.weights }} ; INC LR12 1 ;;
 {% if bias %} MULT.EE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ;
 {% else %} MULT.RC.VV {{ index }} R1 0 LR0 {{ ds }} {{ qi }} ; {% endif %}
 ACC.ADD {% if next_tap %}; LD.MULT.CYCLIC LR11 {{ cr.windows }} LR2 ; INC LR11 1 {% endif %} ;;
{% endmacro %}
 INC LR2 128 ; LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ;;
 INC LR4 255 ;;
 INC LR4 1 ;;
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR4 ;;
batch:
 SET LR1 LR2 ; SET LR3 LR2 ; SET LR7 CR0 ;;
 DEC LR1 1 ; INC LR3 1 ; SET LR9 CR0 ;;
 INC LR9 {{ in0_d1 }} ; DEC LR7 1 ;;
stage_channel:
 SET LR6 LR5 ; SET LR8 CR0 ;;
 INC LR8 {{ in0_d3 }} ;;
 {{ zero_window() }}
stage_y:
 LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR2 ;;
 {% for x in range(3) %}{{ stage_tap(x) }}{% endfor %}
 DEC LR8 1 ; INC LR6 {{ in0_d1 }} ;;
 BNE LR8 CR0 stage_y ;;
 {{ zero_window() }}
 INC LR5 1 ; DEC LR9 1 ;;
 BNE LR9 CR0 stage_channel ;;
 ADD LR5 LR5 {{ cr.batch_jump }} ; SET LR1 CR0 ; SET LR6 CR1 ;;
group:
 SET LR3 CR0 ;;
 INC LR3 {{ ocg }} ;;
channel:
 SET LR7 LR1 ; SET LR8 CR0 ;;
 INC LR8 {{ out0_d3 }} ;;
packed_y:
 SET LR12 LR6 ; SET LR9 CR0 ; SET LR10 LR2 ;;
 INC LR9 1 ; DEC LR12 1 ;;
 {{ digits('LR0', first=true, bias=true) }}
member:
 ADD LR12 LR6 CR1 ; SET LR11 LR7 ; SET LR13 CR0 ;;
 DEC LR11 1 ; INC LR13 {{ icg }} ;;
input_channel:
 LD.MULT.CYCLIC LR11 {{ cr.windows }} LR2 ; INC LR11 1 ;;
 {% for tap in range(9) %}
 {{ digits('LR10', next_tap=(tap < 8)) }}
 {% endfor %}
 DEC LR13 1 ; ADD LR11 LR11 {{ cr.next_plane }} ;;
 BNE LR13 CR0 input_channel ;;
 INC LR7 {{ 3 * stride }} ; DEC LR10 {{ out0_d2 }} ; DEC LR9 1 ;;
 BNE LR9 CR0 member ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.width }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; DEC LR8 1 ;;
 INC LR14 1 ; BNE LR8 CR0 packed_y ;;
 ADD LR6 LR12 CR1 ; DEC LR3 1 ;;
 BNE LR3 CR0 channel ;;
 ADD LR1 LR1 {{ cr.group_plane }} ; BLT.S LR6 {{ cr.weight_rows }} group ;;
 DEC LR15 1 ;;
 BNE LR15 CR0 batch ;;
 HALT ;;
