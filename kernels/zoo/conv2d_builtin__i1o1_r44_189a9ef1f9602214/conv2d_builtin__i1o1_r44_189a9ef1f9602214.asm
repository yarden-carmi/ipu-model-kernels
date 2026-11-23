{% macro add_imm(reg, count) %}
{% for i in range(0, count|abs, 255) %}
 {{ 'INC' if count > 0 else 'DEC' }} {{ reg }} {{ [255, (count|abs)-i]|min }} ;;
{% endfor %}
{% endmacro %}

{% macro fetch() %}LD.MULT.CYCLIC LR4 {{ cr.weights }} LR12{% endmacro %}

{% macro dot(more) %}
 MULT.RC.VV LR12 R0 0 LR12 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.input_ds }}.L ; INC LR4 1 ; {{ fetch() }} ;;
 MULT.RC.VV LR12 R0 0 LR12 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.input_ds }}.L ; INC LR4 1 {% if more %}; {{ fetch() }}{% endif %} ;;
 INC LR11 1 ;;
{% endmacro %}

{% macro block(tag, count, ds) %}
 SET LR13 CR0 ; SET LR15 CR0 ;;
 {{ add_imm('LR13', ((count-1)//16)*16-1) }}
 {{ add_imm('LR15', 2*count) }}
 {{ fetch() }} ; SET LR5 CR0 ;;
 MULT.RC.VE LR12 CR1 0 LR12 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR4 1 ; {{ fetch() }} ;;
 MULT.RC.VE LR12 CR1 0 LR12 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR7 LR2 ; INC LR4 1 ; DEC LR5 1 ;;
 SUB LR7 LR7 {{ cr.in0_d3 }} ;;
ky{{ tag }}:
 SET LR6 CR0 ; ADD LR8 LR0 LR5 ;;
 DEC LR6 1 ;;
 BLT.S LR8 CR0 skip_y{{ tag }} ;;
 BGE.S LR8 {{ cr.in0_d2 }} skip_y{{ tag }} ;;
kx{{ tag }}:
 ADD LR8 LR1 LR6 ; ADD LR9 LR7 LR6 ; SET LR11 CR0 ;;
 BLT.S LR8 CR0 skip_x{{ tag }} ;;
 BGE.S LR8 {{ cr.in0_d3 }} skip_x{{ tag }} ;;
 LD.MULT R0 LR9 {{ cr.in0 }} ;;
 {{ fetch() }} ;;
{% if count > 16 %}
channels{{ tag }}:
{% for i in range(16) %}
 {{ dot(true) }}
{% endfor %}
 BLT.S LR11 LR13 channels{{ tag }} ;;
{% endif %}
{% for i in range((count-1)%16) %}
 {{ dot(true) }}
{% endfor %}
 {{ dot(false) }}
 BEQ LR12 CR0 next_x{{ tag }} ;;
skip_y{{ tag }}:
 ADD LR4 LR4 LR15 ;;
 ADD LR4 LR4 LR15 ;;
 ADD LR4 LR4 LR15 ;;
 BEQ LR12 CR0 next_y{{ tag }} ;;
skip_x{{ tag }}:
 ADD LR4 LR4 LR15 ;;
next_x{{ tag }}:
 INC LR6 1 ; BLT.S LR6 CR1 kx{{ tag }} ;;
next_y{{ tag }}:
 INC LR5 1 ; ADD LR7 LR7 {{ cr.in0_d3 }} ; BLT.S LR5 CR1 ky{{ tag }} ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
 INC LR3 1 ;;
{% endmacro %}

 SET LR12 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
{% if in0_d2 == 1 or in0_d3 == 1 %}
 {# Degenerate axes may never use some taps, but all constants are handed. #}
 SET LR4 CR0 ; SET LR14 CR0 ;;
 {{ add_imm('LR14', 2*((out0_d1+127)//128) + 18*out0_d1) }}
read_constants:
 {{ fetch() }} ;;
 INC LR4 1 ;;
 BLT.S LR4 LR14 read_constants ;;
{% endif %}
batch:
 SET LR0 CR0 ;;
oy:
 SET LR1 CR0 ;;
ox:
 SET LR4 CR0 ;;
{% if out0_d1 > 128 %}
 {{ block('full', 128, cr.full) }}
{% endif %}
 {{ block('tail', (out0_d1-1)%128+1, cr.tail) }}
 INC LR1 {{ stride }} ; INC LR2 {{ stride }} ;;
 BLT.S LR1 {{ cr.x_end }} ox ;;
 ADD LR2 LR2 {{ cr.row_fix }} ; INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.y_end }} oy ;;
 ADD LR2 LR2 {{ cr.batch_fix }} ; DEC LR10 1 ;;
 BLT.S CR0 LR10 batch ;;
 HALT ;;
