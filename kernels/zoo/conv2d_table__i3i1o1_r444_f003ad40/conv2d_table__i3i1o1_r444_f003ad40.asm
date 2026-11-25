{# One output pixel and channel chunk per accumulation. Alternate cyclic
   slots so a weight fetch can overlap the previous weight's MAC. #}
{% set ic = (in1_d1 + 127) // 128 %}
{% set oc = (out0_d1 + 127) // 128 %}
{% set iw = in1_d3 %}
{% set ow = out0_d3 %}
{% macro shift(r, n) %}
{% for k in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255, n|abs-k]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro mac(slot, next, src, first=false, extra='') %}
 MULT.RC.VE {{ slot }} {{ src }} 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_in1 }}.L ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }} ; INC LR13 1 ; LD.MULT.CYCLIC LR13 {{ cr.weights }} {{ next }}{{ extra }} ;;
{% endmacro %}
{% macro chunk(tag, count) %}
 LD.MULT R0 LR4 {{ cr.in1 }} ; INC LR4 1 ; SET LR9 CR0 ; SET LR15 CR0 ;;
 DEC LR9 1 ;;
 {{ shift('LR15', count - 1) }}
{{ tag }}:
 {{ mac('LR0', 'LR1', 'LR9', extra=' ; INC LR9 1') }}
 {{ mac('LR1', 'LR0', 'LR9', extra=(' ; BLT.S LR9 LR15 ' ~ tag) if count > 1 else '') }}
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
 SET LR2 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
 {{ shift('LR10', ow - 1) }}
 {{ shift('LR11', out0_d2 - 1) }}
 SET LR14 CR0 ;;
output_chunk:
 SET LR5 CR0 ; SET LR7 CR0 ; SET LR8 LR2 ;;
 {{ shift('LR5', -(iw + 1) * ic - 1) }}
output_y:
 SET LR6 CR0 ;;
pixel:
 SET LR4 LR5 ; SET LR13 LR14 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 {{ mac('LR0', 'LR1', 'CR1', true) }}
 {{ mac('LR1', 'LR0', 'CR1') }}
{% for t in range(9) %}
{% if t < 3 %} BEQ LR7 CR0 skip{{ t }} ;; {% endif %}
{% if t >= 6 and (stride == 1 or in1_d2 % 2) %} BEQ LR7 LR11 skip{{ t }} ;; {% endif %}
{% if t % 3 == 0 %} BEQ LR6 CR0 skip{{ t }} ;; {% endif %}
{% if t % 3 == 2 and (stride == 1 or iw % 2) %} BEQ LR6 LR10 skip{{ t }} ;; {% endif %}
{% if ic > 1 %}
 SET LR12 CR0 ;;
 INC LR12 {{ ic - 1 }} ;;
full{{ t }}:
 {{ chunk('full_channels' ~ t, 128) }}
 DEC LR12 1 ;;
 BNE LR12 CR0 full{{ t }} ;;
{% endif %}
 {{ chunk('tail_channels' ~ t, cin - (ic - 1) * 128) }}
after{{ t }}:
{% if t in [2, 5] %}
 {{ shift('LR4', (iw - 3) * ic) }}
{% endif %}
{% endfor %}
 ACTIVATE.QUANTIZE generic {{ cr.ds128 }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ; INC LR5 {{ stride * ic }} ; INC LR6 1 ; BLT.S LR6 LR10 pixel_next ;;
 INC LR8 {{ oc }} ; INC LR7 1 ; BLT.S LR7 LR11 row_next ;;
 INC LR2 1 ; ADD LR14 LR14 {{ cr.orows }} ;;
 BLT.S LR2 {{ cr.oc }} output_chunk ;;
 HALT ;;
pixel_next:
 INC LR8 {{ oc }} ; BEQ CR0 CR0 pixel ;;
row_next:
 {{ shift('LR5', stride * (iw - ow) * ic) }}
 BEQ CR0 CR0 output_y ;;

{% for t in range(9) if t != 4 %}
skip{{ t }}:
 {{ shift('LR13', 2 * cin) }}
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR4 {{ ic }} ; BEQ CR0 CR0 after{{ t }} ;;
{% endfor %}
