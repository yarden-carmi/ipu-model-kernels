{% set ds = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set ib = (in0_d1 + 127) // 128 %}
{% macro setnum(reg, value) %}
 SET {{reg}} CR0 ;;
 {% if value >= 16384 %}
 INC {{reg}} {{value // 16384}} ;;
 {% for i in range(7) %} ADD {{reg}} {{reg}} {{reg}} ;; {% endfor %}
 {% endif %}
 {% if value >= 128 %}
 {% if (value // 128) % 128 %} INC {{reg}} {{(value // 128) % 128}} ;; {% endif %}
 {% for i in range(7) %} ADD {{reg}} {{reg}} {{reg}} ;; {% endfor %}
 {% endif %}
 {% if value % 128 %} INC {{reg}} {{value % 128}} ;; {% endif %}
{% endmacro %}
{% macro digit(src, acc) %}
 LD.MULT.CYCLIC LR7 {{cr.weights}} LR0 ;;
 INC LR7 1 ; MULT.RC.VE LR0 {{src}} 0 LR0 {{ds}} {{qi}} ; {{acc}} ;;
{% endmacro %}
{% macro tap_digit() %}
 LD.MULT.CYCLIC LR7 {{cr.weights}} LR0 ;;
 MULT.RC.VE LR0 LR12 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR12 128 ;;
 MULT.RC.VE LR0 LR12 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; DEC LR12 128 ; INC LR7 1 ;;
{% endmacro %}
{% macro skip_tap() %}
 {% for i in range(0, 2 * cin, 255) %} INC LR7 {{[255, 2 * cin - i] | min}} ;; {% endfor %}
{% endmacro %}

{# Transpose packed channel-major input to spatial-major rows. #}
SET LR4 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
SET LR9 CR0 ;;
{{setnum('LR13', channel_rows)}}
{{setnum('LR14', in0_d2 * in0_d3)}}
transpose_pixel:
 SET LR5 LR9 ;;
 {% for b in range(ib) %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR6 CR0 ;;
 MULT.EE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ;;
 transpose_channel_{{b}}:
 LD.MULT R0 LR5 {{cr.in0}} ;;
 MULT.EE LR4 CR1 0 LR0 {{ds}} {{qi}} ; ACC.RESHAPE LRD0 LRD2 7 ;;
 ADDBI LRD2 1 ; ADD LR5 LR5 LR13 ; INC LR6 1 ;;
 {{setnum('LR10', [128, in0_d1 - b * 128] | min)}}
 BLT.S LR6 LR10 transpose_channel_{{b}} ;;
 ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.transposed}} LR7 ;;
 LD.MULT R0 LR7 {{cr.transposed}} ;;
 MULT.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.SUB ;;
 {{setnum('LR10', in0_d2 * in0_d3 * ib)}}
 ADD LR10 LR10 LR7 ;;
 ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.transposed}} LR10 ;;
 INC LR7 1 ;;
 {% endfor %}
 INC LR8 1 ; INC LR4 1 ;;
 {{setnum('LR10', 128)}}
 BLT.S LR4 LR10 transpose_nowrap ;;
 SET LR4 CR0 ; INC LR9 1 ;;
 transpose_nowrap:
 BLT.S LR8 LR14 transpose_pixel ;;

 SET LR0 CR0 ; SET LR6 CR0 ; SET LR1 CR0 ;;
 SET LR15 CR0 ;;
 {% for p in range(padding) %} SUB LR1 LR1 {{cr.row_step}} ;; {% endfor %}
 {% if padding %} DEC LR1 {{padding * ib}} ;; {% endif %}
 SET LR2 LR1 ; SET LR4 CR0 ;;
 {% if padding %} DEC LR4 {{padding}} ;; {% endif %}
line:
 SET LR3 LR2 ; SET LR5 CR0 ;;
 {% if padding %} DEC LR5 {{padding}} ;; {% endif %}
pixel:
 SET LR7 CR0 ; SET LR6 CR0 ;;
block:
 SET LR8 LR3 ; SET LR10 LR4 ;;
 SET LR13 LR4 ; SET LR14 LR5 ;;
 INC LR13 {{kh}} ; INC LR14 {{kw}} ;;
 {{digit('CR1', 'ACC.ADD.FIRST')}}
 {{digit('CR1', 'ACC.ADD')}}
ky:
 BLT.S LR10 CR0 skip_line ;;
 BGE.S LR10 {{cr.in0_d2}} skip_line ;;
 SET LR9 LR5 ; SET LR11 LR8 ;;
kx:
 BLT.S LR9 CR0 skip_column ;;
 BGE.S LR9 {{cr.in0_d3}} skip_column ;;
 {% for b in range(ib) %}
 LD.MULT R0 LR11 {{cr.transposed}} ; SET LR12 CR0 ;;
 {{setnum('LR1', in0_d2 * in0_d3 * ib)}}
 ADD LR1 LR1 LR11 ;;
 LD.MULT R1 LR1 {{cr.transposed}} ;;
 {{setnum('LR1', [128, cin - b * 128] | min)}}
 channel_{{b}}:
 {{tap_digit()}}
 {{tap_digit()}}
 INC LR12 1 ;;
 BLT.S LR12 LR1 channel_{{b}} ;;
 {% if not loop.last %} INC LR11 1 ;; {% endif %}
 {% endfor %}
 {% if ib > 1 %} DEC LR11 {{ib - 1}} ;; {% endif %}
 B next_column ;;
skip_column:
 {{skip_tap()}}
next_column:
 INC LR9 1 ; INC LR11 {{ib}} ;;
 BLT.S LR9 LR14 kx ;;
 B next_line ;;
skip_line:
 SET LR9 LR5 ;;
skip_line_tap:
 {{skip_tap()}}
 INC LR9 1 ;;
 BLT.S LR9 LR14 skip_line_tap ;;
next_line:
 INC LR10 1 ; ADD LR8 LR8 {{cr.row_step}} ;;
 BLT.S LR10 LR13 ky ;;

{# Preserve the accumulated value as several quantized residual digits. #}
 {{setnum('LR8', 2 * in0_d2 * in0_d3 * ib)}}
 {% for digit in range(5) %}
 ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.transposed}} LR8 ;;
 {% if not loop.last %}
 LD.MULT R0 LR8 {{cr.transposed}} ;;
 MULT.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.SUB ;;
 {% endif %}
 INC LR8 1 ;;
 {% endfor %}
 LD.MULT R1 LR6 {{cr.scales}} ;;
 {% for digit in range(5) %}
 {{setnum('LR8', 2 * in0_d2 * in0_d3 * ib + digit)}}
 LD.MULT.CYCLIC LR8 {{cr.transposed}} LR0 ;;
 MULT.RC.VV LR0 R1 0 LR0 {{ds}} {{qi}} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 BGE.S LR7 {{cr.weight_rows}} last_block ;;
 ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.ds_pair}}.L {{cr.qf_out0}}.L {{cr.out0}} LR15 ;;
 INC LR15 1 ; INC LR6 1 ;;
 B block ;;
last_block:
 ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.ds_pair}}.H {{cr.qf_out0}}.L {{cr.out0}} LR15 ;;
 INC LR15 1 ; INC LR3 {{stride * ib}} ; INC LR5 {{stride}} ;;
 BLT.S LR5 {{cr.end_x}} pixel ;;
 {% for s in range(stride) %} ADD LR2 LR2 {{cr.row_step}} ;; {% endfor %}
 INC LR4 {{stride}} ;;
 BLT.S LR4 {{cr.end_y}} line ;;
 HALT ;;
