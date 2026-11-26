{% set w9 = cr.f9 if format == 'fp32' else cr.k9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.k3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.k1 %}
{% macro tap(row, lane, weight, acc, store=false) %}
 LD.MULT R0 {{ row }} {{ cr.in0 }} ;;
 MULT.VE {{ lane }} {{ weight }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; {{ acc }}{% if store %} ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR7{% endif %} ;;
{% endmacro %}
{% macro pixel(lane, other_lane, other_top, other_bottom) %}
 {{ tap('LR3', lane, w9, 'ACC.ADD.FIRST') }}
 {{ tap(other_top, other_lane, w3, 'ACC.ADD') }}
 {{ tap('LR4', lane, w3, 'ACC.ADD') }}
 {{ tap(other_bottom, other_lane, w1, 'ACC.ADD', true) }}
 INC LR7 1 ;;
{% endmacro %}
{% macro scan(tag) %}
 SET LR3 LR1 ; SET LR4 LR2 ; SET LR9 {{ cr.pitch }} ;;
{{ tag }}_pair:
 BEQ LR9 {{ cr.pitch }} {{ tag }}_left_edge ;;
 SUB LR5 LR3 CR1 ; SUB LR6 LR4 CR1 ; SET LR11 LR15 ; BNE CR0 CR1 {{ tag }}_left_ready ;;
{{ tag }}_left_edge:
 SET LR5 LR3 ; SET LR6 LR4 ; SET LR11 CR0 ;;
{{ tag }}_left_ready:
 {{ pixel('LR0', 'LR11', 'LR5', 'LR6') }}
 {{ pixel('LR0', 'LR15', 'LR3', 'LR4') }}
 {{ pixel('LR15', 'LR0', 'LR3', 'LR4') }}
 BEQ LR9 CR1 {{ tag }}_right_edge ;;
 ADD LR5 LR3 CR1 ; ADD LR6 LR4 CR1 ; SET LR11 CR0 ; BNE CR0 CR1 {{ tag }}_right_ready ;;
{{ tag }}_right_edge:
 SET LR5 LR3 ; SET LR6 LR4 ; SET LR11 LR15 ;;
{{ tag }}_right_ready:
 {{ pixel('LR15', 'LR11', 'LR5', 'LR6') }}
 INC LR3 1 ; INC LR4 1 ; DEC LR9 1 ;;
 BNE LR9 CR0 {{ tag }}_pair ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
 SET LR10 LR14 ;;
batch:
 SET LR8 {{ cr.in0_d2 }} ;;
source_y:
 SET LR2 LR1 ; BEQ LR8 {{ cr.in0_d2 }} upper_ready ;;
 SUB LR2 LR1 {{ cr.pitch }} ;;
upper_ready:
 {{ scan('upper') }}
 SET LR2 LR1 ; BEQ LR8 CR1 lower_ready ;;
 ADD LR2 LR1 {{ cr.pitch }} ;;
lower_ready:
 {{ scan('lower') }}
 ADD LR1 LR1 {{ cr.pitch }} ; DEC LR8 1 ;;
 BNE LR8 CR0 source_y ;;
 DEC LR10 1 ;;
 BNE LR10 CR0 batch ;;
 // Transpose the quantized pixel rows into channel-major packed output rows.
 SET LR8 LR7 ; SET LR0 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR10 CR0 ;;
trans_row:
 SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
 SET LR7 CR0 ; SET LR11 CR0 ; SET LR1 LR3 ;;
 INC LR11 8 ;;
trans_channel:
 SET LR9 CR0 ;;
trans_lane:
 LD.MULT R0 LR2 {{ cr.tmp }} ;;
 MULT.EE LR1 CR1 0 LR0 {{ cr.active }}.H {{ cr.qf_out0 }}.L ; ACC.RESHAPE LRD6 LRD4 0 ;;
 ADDBI LRD4 1 ; INC LR2 1 ; INC LR9 1 ;;
 BLT.S LR9 LR12 trans_lane ;;
 DEC LR11 1 ;;
 BNE LR11 CR0 trans_channel ;;
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
 INC LR10 1 ;;
 BLT.S LR2 LR8 trans_row ;;
 SET LR2 CR0 ; INC LR3 1 ;;
 BLT.S LR3 LR15 trans_row ;;
 HALT ;;
