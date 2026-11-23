{# LR0/LR1: window center y/x; LR2: its input row; LR3: output row.
   LR4 walks folded rows in pixel/tap/channel order; LR5 is packed occupancy.
   LR15 is the cyclic base and mask shift, both zero. #}
{% macro mac(src, first='ACC.ADD') %}
 MULT.RC.VE LR15 {{ src }} 0 LR15 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; {{ first }} ; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; INC LR4 1 ;;
 MULT.RC.VE LR15 {{ src }} 0 LR15 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 ;;
{% endmacro %}

{% macro prime() %}
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
{% endmacro %}

{% macro kernel_row(ky) %}
{% set dy = ky - padding %}
{% if dy != 0 %}
 SET LR6 LR0 ;;
 {{ 'INC' if dy > 0 else 'DEC' }} LR6 {{ dy|abs }} ;;
 {% if dy < 0 %}BLT.S LR6 CR0{% else %}BGE.S LR6 {{ cr.in0_d2 }}{% endif %} skip_y{{ ky }} ;;
{% endif %}
{% for kx in range(kw) %}
 {{ tap(ky, kx) }}
{% endfor %}
{% if dy != 0 %}
 BEQ LR15 CR0 end_y{{ ky }} ;;
skip_y{{ ky }}:
{% for kx in range(kw) %}
 ADD LR4 LR4 {{ cr.tap_rows }} ;;
{% endfor %}
end_y{{ ky }}:
{% endif %}
{% endmacro %}

{% macro tap(ky, kx) %}
{% set dx = kx - padding %}
{% set offset = (ky - padding) * in0_d3 + dx %}
{% if dx != 0 %}
 SET LR7 LR1 ;;
 {{ 'INC' if dx > 0 else 'DEC' }} LR7 {{ dx|abs }} ;;
 {% if dx < 0 %}BLT.S LR7 CR0{% else %}BGE.S LR7 {{ cr.in0_d3 }}{% endif %} skip_{{ ky }}_{{ kx }} ;;
{% endif %}
{% if offset != 0 %}
 SET LR8 LR2 ;;
 {{ 'INC' if offset > 0 else 'DEC' }} LR8 {{ offset|abs }} ;;
{% endif %}
 LD.MULT R0 {{ 'LR8' if offset else 'LR2' }} {{ cr.in0 }} ; SET LR9 CR0 ;;
{% if in0_d1 > 1 %}
channel_{{ ky }}_{{ kx }}:
{% endif %}
 {{ prime() }}
 {{ mac('LR9') }}
{% if in0_d1 > 1 %}
 INC LR9 1 ;;
 BLT.S LR9 {{ cr.in0_d1 }} channel_{{ ky }}_{{ kx }} ;;
{% endif %}
{% if dx != 0 %}
 BEQ LR15 CR0 end_{{ ky }}_{{ kx }} ;;
skip_{{ ky }}_{{ kx }}:
 ADD LR4 LR4 {{ cr.tap_rows }} ;;
end_{{ ky }}_{{ kx }}:
{% endif %}
{% endmacro %}

{% macro store() %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
{% endmacro %}

 SET LR15 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 SET LR4 CR0 ; SET LR5 CR0 ;;
batch:
 SET LR0 CR0 ;;
oy:
 SET LR1 CR0 ;;
pixel:
 {{ prime() }}
 BNE LR5 CR0 more_bias ;;
 {{ mac('CR1', 'ACC.ADD.FIRST') }}
 BEQ LR15 CR0 taps ;;
more_bias:
 {{ mac('CR1') }}
taps:
{% for ky in range(kh) %}
 {{ kernel_row(ky) }}
{% endfor %}
 INC LR5 1 ; INC LR1 {{ stride }} ; INC LR2 {{ stride }} ;;
 BLT.S LR5 {{ cr.pack }} advance ;;
 {{ store() }}
 INC LR3 1 ; SET LR5 CR0 ; SET LR4 CR0 ;;
advance:
 BLT.S LR1 {{ cr.x_end }} pixel ;;
 INC LR0 {{ stride }} ; ADD LR2 LR2 {{ cr.x_fix }} ;;
 BLT.S LR0 {{ cr.y_end }} oy ;;
 DEC LR10 1 ; ADD LR2 LR2 LR14 ;;
 BLT.S CR0 LR10 batch ;;
 BEQ LR5 CR0 finish ;;
 {{ store() }}
finish:
 HALT ;;
