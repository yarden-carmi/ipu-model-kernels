{% set ds = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set ib = (in0_d1 + 127) // 128 %}
{% set ob = (out0_d1 + 127) // 128 %}
{% macro digit(src, acc) %}
 LD.MULT.CYCLIC LR7 {{ cr.weights }} LR0 ;;
 INC LR7 1 ; MULT.RC.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qi }} ; {{ acc }} ;;
{% endmacro %}
{% macro skip_tap() %}
 {% for i in range(0, 2 * cin, 255) %} INC LR7 {{[255, 2 * cin - i] | min}} ;; {% endfor %}
{% endmacro %}
{% macro setnum(reg, value) %}
 SET {{reg}} CR0 ;;
 {% if value >= 16384 %}
 INC {{reg}} {{value // 16384}} ;;
 {% for i in range(7) %} ADD {{reg}} {{reg}} {{reg}} ;; {% endfor %}
 {% endif %}
 {% if value >= 128 %}
 {% if (value // 128) % 128 %}INC {{reg}} {{(value // 128) % 128}} ;;{% endif %}
 {% for i in range(7) %} ADD {{reg}} {{reg}} {{reg}} ;; {% endfor %}
 {% endif %}
 {% if value % 128 %} INC {{reg}} {{value % 128}} ;; {% endif %}
{% endmacro %}
{% macro save_digits(half) %}
 {% for digit in range(5) %}
 ACTIVATE.QUANTIZE identity {{cr.ds_pair}}.{{half}} {{cr.qf_out0}}.L {{cr.tmp}} LR6 ;;
 {% if not loop.last %}
 LD.MULT R0 LR6 {{cr.tmp}} ;;
 MULT.VE LR0 CR1 0 LR0 {{ds}} {{cr.qf_out0}}.L ; ACC.SUB ;;
 {% endif %}
 INC LR6 1 ;;
 {% endfor %}
{% endmacro %}
 SET LR0 CR0 ; SET LR6 CR0 ; SET LR1 CR0 ;;
 {% for p in range(padding) %} SUB LR1 LR1 {{cr.row_step}} ;; {% endfor %}
 {% if padding %} DEC LR1 {{padding * ib}} ;; {% endif %}
 SET LR2 LR1 ; SET LR4 CR0 ;;
 {% if padding %} DEC LR4 {{padding}} ;; {% endif %}
line:
 SET LR3 LR2 ; SET LR5 CR0 ;;
 {% if padding %} DEC LR5 {{padding}} ;; {% endif %}
pixel:
 SET LR7 CR0 ;;
block:
 SET LR8 LR3 ; SET LR10 LR4 ;;
 SET LR13 LR4 ; SET LR14 LR5 ;;
 INC LR13 {{kh}} ; INC LR14 {{kw}} ;;
 {{ digit('CR1', 'ACC.ADD.FIRST') }}
 {{ digit('CR1', 'ACC.ADD') }}
ky:
 BLT.S LR10 CR0 skip_line ;;
 BGE.S LR10 {{cr.in0_d2}} skip_line ;;
 SET LR9 LR5 ; SET LR11 LR8 ;;
kx:
 BLT.S LR9 CR0 skip_column ;;
 BGE.S LR9 {{cr.in0_d3}} skip_column ;;
 {% for b in range(ib) %}
 LD.MULT R0 LR11 {{cr.in0}} ; SET LR12 CR0 ;;
 {% set count = [128, cin - b * 128] | min %}
 {{setnum('LR15', count - 1)}}
 DEC LR12 1 ;;
 LD.MULT.CYCLIC LR7 {{ cr.weights }} LR0 ;;
channel_{{b}}:
 MULT.RC.VE LR0 LR12 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; LD.MULT.CYCLIC LR7 {{cr.weights}} LR0 ; INC LR7 1 ; INC LR12 1 ;;
 MULT.RC.VE LR0 LR12 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; LD.MULT.CYCLIC LR7 {{cr.weights}} LR0 ; INC LR7 1 ; BLT.S LR12 LR15 channel_{{b}} ;;
 {% if not loop.last %}INC LR11 1 ;;{% endif %}
 {% endfor %}
 {% if ib > 1 %}DEC LR11 {{ib - 1}} ;;{% endif %}
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
 BGE.S LR7 {{cr.weight_rows}} last_block ;;
 {{save_digits('L')}}
 B block ;;
last_block:
 {{save_digits('H')}}
 INC LR3 {{stride * ib}} ; INC LR5 {{stride}} ;;
 BLT.S LR5 {{cr.end_x}} pixel ;;
 {% for s in range(stride) %} ADD LR2 LR2 {{cr.row_step}} ;; {% endfor %}
 INC LR4 {{stride}} ;;
 BLT.S LR4 {{cr.end_y}} line ;;
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
 SET LR5 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
 {{setnum('LR14', out0_d1)}}
 {{setnum('LR15', out0_d2 * out0_d3)}}
{% macro gather_digit(tag, digit) %}
 SET LR10 LR6 ; SET LR11 LR13 ;;
 {% if digit %}INC LR10 {{digit}} ;;{% endif %}
 SET LR2 CR0 ; SET LR3 CR0 ;;
 SET LR7 CR0 ;;
 MULT.EE LR0 CR0 0 LR0 {{ds}} {{cr.qf_out0}}.L ; ACC.ADD.FIRST ;;
gather_{{tag}}:
 LD.MULT R0 LR10 {{cr.tmp}} ;;
 MULT.EE LR4 CR1 0 LR0 {{ds}} {{cr.qf_out0}}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
 ADDBI LRD2 1 ;;
 INC LR7 1 ;;
 INC LR11 1 ;;
 INC LR10 {{5 * ob}} ;;
 {{setnum('LR12', [128, 8 * out0_d3] | min)}}
 BEQ LR7 LR12 gather_done_{{tag}} ;;
 BLT.S LR11 LR15 gather_{{tag}} ;;
gather_done_{{tag}}:
 {{setnum('LR12', 5 * out0_d2 * out0_d3 * ob + digit)}}
 ACTIVATE.QUANTIZE identity {{ds}} {{cr.qf_out0}}.L {{cr.tmp}} LR12 ;;
{% endmacro %}
channel_out:
 SET LR6 LR5 ; SET LR13 CR0 ;;
chunk:
 {% for digit in range(5) %}{{gather_digit('d' ~ digit, digit)}}{% endfor %}
 SET LR6 LR10 ; SET LR13 LR11 ;;
 DEC LR6 4 ;;
 {{setnum('LR12', 5 * out0_d2 * out0_d3 * ob)}}
 LD.MULT.CYCLIC LR12 {{cr.tmp}} LR0 ;;
 LD.MULT R1 LR9 {{cr.scales}} ;;
 SET LR12 CR0 ;;
 INC LR12 128 ;;
 MULT.RC.VE LR0 LR12 0 LR0 {{ds}} {{cr.qf_out0}}.L ; ACC.ADD.FIRST ;;
 {% for digit in range(1, 5) %}
 {{setnum('LR12', 5 * out0_d2 * out0_d3 * ob + digit)}}
 LD.MULT.CYCLIC LR12 {{cr.tmp}} LR0 ;;
 SET LR12 CR0 ;;
 INC LR12 128 ;;
 MULT.RC.VE LR0 LR12 0 LR0 {{ds}} {{cr.qf_out0}}.L ; ACC.ADD ;;
 {% endfor %}
 ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{ds}} {{cr.qf_out0}}.L {{cr.out0}} LR8 ;;
 INC LR8 1 ;;
 BLT.S LR11 LR15 chunk ;;
 INC LR4 1 ; INC LR9 1 ;;
 SET LR12 CR0 ;;
 INC LR12 128 ;;
 BLT.S LR4 LR12 no_wrap ;;
 SET LR4 CR0 ; INC LR5 5 ;;
no_wrap:
 BLT.S LR9 LR14 channel_out ;;
 HALT ;;
