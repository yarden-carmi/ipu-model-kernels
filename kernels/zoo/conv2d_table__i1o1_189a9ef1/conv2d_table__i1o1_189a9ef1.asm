{# Channels on lanes. Dense convolution broadcasts one input lane; depthwise
   convolution multiplies corresponding lanes. Both stream two weight frames. #}
{% set wp = w + 2 * padding %}
{% set wo = (wp - kw) // stride + 1 %}
{% set ho = (h + 2 * padding - kh) // stride + 1 %}
{% set depthwise = groups == cin and groups == cout %}
{% set channels = 1 if depthwise else cin %}
{% macro step(r, n) %}
{% for k in range(0, n|abs, 255) %}
 {{ 'INC' if n >= 0 else 'DEC' }} {{ r }} {{ [255, (n|abs)-k]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro zero() %}
 MULT.VE LR0 CR0 0 LR0 {{ cr.dsi }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.dsi }}.L {{ cr.qf_in0 }}.L {{ cr.pad }} LR9 ; INC LR9 1 ;;
{% endmacro %}
{% macro zero_loop(label, count) %}
 SET LR13 CR0 ; SET LR14 CR0 ;;
 {{ step('LR14', count) }}
{{ label }}:
 {{ zero() }}
 INC LR13 1 ;;
 BLT.S LR13 LR14 {{ label }} ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ;;
 DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}

{# Materialize a halo in the input's own format. #}
 SET LR9 CR0 ; SET LR10 CR0 ; SET LR12 CR0 ;;
 DEC LR9 1 ; SET LR15 CR0 ; SET LR3 CR0 ;;
 {{ step('LR15', h) }}
 {{ step('LR3', w) }}
 DEC LR10 1 ;;
 LD.MULT R0 LR0 {{ cr.in0 }} ;;
 {{ zero_loop('top', padding * wp + padding) }}
copy_y:
 SET LR11 CR0 ;;
copy_x:
 LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR10 1 ; INC LR11 1 ;;
 MULT.VE LR0 CR1 0 LR0 {{ cr.dsi }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.dsi }}.L {{ cr.qf_in0 }}.L {{ cr.pad }} LR9 ; INC LR9 1 ; BLT.S LR11 LR3 copy_x ;;
{% for i in range(2 * padding) %}
 {{ zero() }}
{% endfor %}
 INC LR12 1 ;;
 BLT.S LR12 LR15 copy_y ;;
 {{ zero_loop('bottom', padding * wp - padding) }}

{% macro pair(src, op, first=false, loop='') %}
 {{ op }} LR0 {{ src }} 0 LR0 {{ cr.dso }}.L {{ cr.qf_weights }}.L ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }} ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 {{ op }} LR1 {{ src }} 0 LR0 {{ cr.dso }}.L {{ cr.qf_weights }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
{% if loop %}
 INC LR2 1 ; BLT.S LR2 LR3 {{ loop }} ;;
{% endif %}
{% endmacro %}

 SET LR3 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
 SET LR7 CR0 ; SET LR8 CR0 ; SET LR10 CR0 ;;
 DEC LR8 1 ; SET LR11 CR0 ;;
 {{ step('LR3', channels - 1) }}
 {{ step('LR10', wo) }}
 {{ step('LR11', ho) }}
pixel:
 SET LR4 LR5 ; SET LR13 CR0 ;;
 DEC LR4 1 ; DEC LR13 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 {{ pair('CR1', 'MULT.RC.VE', first=true) }}
{% for t in range(kh * kw) %}
 LD.MULT R0 LR4 {{ cr.pad }} ; SET LR2 CR0 ; INC LR4 1 ;;
{% if depthwise %}
 {{ pair('R0', 'MULT.RC.VV') }}
{% elif channels == 1 %}
 {{ pair('LR2', 'MULT.RC.VE') }}
{% else %}
channel_{{ t }}:
 {{ pair('LR2', 'MULT.RC.VE', loop='channel_' ~ t) }}
{% endif %}
{% if (t + 1) % kw == 0 and t + 1 < kh * kw %}
 {{ step('LR4', wp - kw) }}
{% endif %}
{% endfor %}
 ACTIVATE.QUANTIZE generic {{ cr.dso }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ; INC LR8 1 ; INC LR5 {{ stride }} ; INC LR6 1 ;;
 BLT.S LR6 LR10 pixel ;;
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5', stride * (wp - wo)) }}
 BLT.S LR7 LR11 pixel ;;
 HALT ;;
