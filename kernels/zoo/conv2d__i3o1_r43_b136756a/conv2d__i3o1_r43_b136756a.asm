{# Set a nonnegative integer with base-2 digits, using only byte immediates. #}
{% macro literal(r, n) %}
 SET {{r}} CR0 ;;
 {% if n >= 256 %}
 {% for bit in range(30, 7, -1) %}
 {% if n // (2 ** bit) %}
 {% if n // (2 ** bit) == 1 %}INC {{r}} 1 ;;{% else %}ADD {{r}} {{r}} {{r}} ;;{% if (n // (2 ** bit)) % 2 %}INC {{r}} 1 ;;{% endif %}{% endif %}
 {% endif %}
 {% endfor %}
 {% for bit in range(7, -1, -1) %}
 ADD {{r}} {{r}} {{r}} ;;{% if (n // (2 ** bit)) % 2 %}INC {{r}} 1 ;;{% endif %}
 {% endfor %}
 {% elif n %}INC {{r}} {{n}} ;;
 {% endif %}
{% endmacro %}

{# Gather each tap into a vector of 128 consecutive output positions. #}
 SET LR15 CR0 ; SET LR14 CR0 ;;
 SET LR13 CR0 ; SET LR12 CR0 ;;
 SET LR0 CR0 ;;
 INC LR0 128 ;;
{% if out0_d1 > ho * wo %}
 DEC LR13 {{stride}} ;;
{% endif %}
gather_tile:
 SET LR11 CR0 ; SET LR8 CR0 ;;
gather_channel:
 SET LR9 CR0 ;;
gather_ky:
 SET LR10 CR0 ;;
gather_kx:
 SET LR6 LR13 ; SET LR5 LR12 ; SET LR7 CR0 ;;
 ADD LR4 LR6 LR10 ; ADD LR3 LR5 LR11 ;;
 MULT.EE LR15 CR0 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ;;
normalize_x:
 BLT.S LR4 LR0 gather_lane ;;
 DEC LR4 128 ; INC LR3 1 ; BEQ LR15 CR0 normalize_x ;;
gather_lane:
 BGE.S LR5 {{cr.yend}} gathered ;;
 BLT.S LR6 CR0 advance_x ;;
 LD.MULT R0 LR3 {{cr.in0}} ;;
 MULT.EE LR4 CR1 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM.FIRST LR7 {{cr.one}}.L ;;
advance_x:
 INC LR6 {{stride}} ; INC LR7 1 ;;
 BGE.S LR6 LR1 wrap_x ;;
 INC LR4 {{stride}} ;;
 BLT.S LR4 LR0 next_lane ;;
 DEC LR4 128 ; INC LR3 1 ;;
next_lane:
 BLT.S LR7 LR0 gather_lane ;;
 BEQ LR15 CR0 gathered ;;
wrap_x:
 SET LR6 CR0 ; SET LR4 LR10 ; ADD LR5 LR5 {{cr.ystep}} ;;
 ADD LR3 LR5 LR11 ; BLT.S LR7 LR0 gather_lane ;;
gathered:
 ACTIVATE.QUANTIZE identity {{cr.full}}.L {{cr.qf_in0}}.L {{cr.patches}} LR14 ;;
 INC LR14 1 ; INC LR10 1 ;;
 {% if kw > 1 %}
 {{literal('LR7', kw)}}
 BLT.S LR10 LR7 gather_kx ;;
 {% endif %}
 INC LR11 {{wb}} ; INC LR9 1 ;;
 {% if kh > 1 %}
 {{literal('LR7', kh)}}
 BLT.S LR9 LR7 gather_ky ;;
 {% endif %}
 {% if in0_d1 > 1 %}
 INC LR8 1 ;;
 {{literal('LR7', in0_d1)}}
 BGE.S LR8 LR7 gathered_tile ;;
 {{literal('LR7', (in0_d2 - kh) * wb)}}
 ADD LR11 LR11 LR7 ; BEQ LR15 CR0 gather_channel ;;
 {% endif %}
gathered_tile:
 SET LR13 LR6 ; SET LR12 LR5 ; BLT.S LR14 LR2 gather_tile ;;

{# Stream one packed row of weights at a time, holding it in R0. #}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR6 CR0 ;;
 {{literal('LR9', tiles)}}
 {{literal('LR11', taps)}}
 {{literal('LR12', (taps + 127) // 128)}}
 {{literal('LR13', (taps - 1) % 128)}}
 {{literal('LR14', 127)}}
output_channel:
 SET LR2 CR0 ; SET LR5 CR0 ;;
output_tile:
 LD.MULT R1 LR1 {{cr.seed}} ; SET LR3 LR2 ; SET LR7 CR0 ; SET LR8 LR0 ;;
 {{literal('LR4', 128)}}
 MULT.VE LR4 CR1 0 LR15 {{cr.full}}.L {{cr.qf_seed}}.L ; ACC.ADD.FIRST ;;
weight_row:
 LD.MULT R0 LR8 {{cr.weights}} ;;
 INC LR8 1 ; INC LR7 1 ; SET LR4 CR0 ;;
 SET LR10 LR14 ;;
 BLT.S LR7 LR12 mac_start ;;
 SET LR10 LR13 ;;
mac_start:
 LD.MULT.CYCLIC LR3 {{cr.patches}} LR15 ;;
 INC LR3 1 ;;
 BGE.S LR4 LR10 mac_last ;;
mac:
 MULT.RC.VE LR15 LR4 0 LR15 {{cr.full}}.L {{cr.qf_weights}}.L ; ACC.ADD ; LD.MULT.CYCLIC LR3 {{cr.patches}} LR15 ;;
 INC LR3 1 ; INC LR4 1 ;;
 BLT.S LR4 LR10 mac ;;
mac_last:
 MULT.RC.VE LR15 LR4 0 LR15 {{cr.full}}.L {{cr.qf_weights}}.L ; ACC.ADD ; BLT.S LR7 LR12 weight_row ;;
 INC LR5 1 ;;
 BGE.S LR5 LR9 output_tail ;;
 ACTIVATE.QUANTIZE {{act_out0|default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR1 ;;
 INC LR1 1 ; ADD LR2 LR2 LR11 ; BEQ LR15 CR0 output_tile ;;
output_tail:
 ACTIVATE.QUANTIZE {{act_out0|default('identity')}} {{cr.tail}}.L {{cr.qf_out0}}.L {{cr.out0}} LR1 ;;
 INC LR1 1 ; INC LR6 1 ; SET LR0 LR8 ;;
 {{literal('LR10', out0_d2)}}
 BLT.S LR6 LR10 output_channel ;;
 HALT ;;
