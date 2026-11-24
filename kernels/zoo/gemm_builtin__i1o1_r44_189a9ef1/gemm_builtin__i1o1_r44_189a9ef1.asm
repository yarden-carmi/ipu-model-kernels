{# Stream one coefficient row ahead. The last MAC does not prefetch,
   so a block never reads beyond its own weights. #}
{% macro coeff_load() -%}
LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1
{%- endmacro %}
{% macro mac(src, op='ACC.ADD') -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{%- endmacro %}
{% macro store(ds) -%}
ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1
{%- endmacro %}
{% if split %}
{# Keep the high/residual representation, but hide the next pixel's bias
   load in the final MAC and the input load in bias accumulation. #}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    DEC LR3 1 ; DEC LR5 1 ; SET LR8 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
split_pixel:
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {{ coeff_load() }} ;;
    {{ mac('CR1') }} ; LD.MULT R0 LR5 {{ cr.in0 }} ; INC LR5 1 ; SUB LR9 LR0 CR1 ;;
    {{ coeff_load() }} ;;
split_high:
    {{ mac('LR9') }} ; {{ coeff_load() }} ; INC LR9 1 ; BLT.S LR9 {{ cr.full_stop }} split_more ;;
    {{ mac('LR9') }} ; {{ store(cr.tail_ds) }} ; SET LR8 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ; BLT.S LR5 {{ cr.tail_stop }} split_pixel ;;
    HALT ;;
split_more:
    {{ mac('LR9') }} ; {{ coeff_load() }} ; B split_high ;;
{% else %}
{% macro chunk(label, length, end_ops='') %}
{{ label }}_load:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; SUB LR9 LR0 CR1 ;;
{% if length > 1 %}
{{ label }}_mac:
    {{ mac('LR9') }} ; {{ coeff_load() }} ; INC LR9 1 ; BLT.S LR9 {{ cr.full_stop if length == 128 else cr.tail_stop }} {{ label }}_mac ;;
{% endif %}
    {{ mac('LR9') }} ; INC LR9 1 {{ end_ops }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    DEC LR3 1 ;;
pixel:
    SUB LR8 LR0 CR1 ; SET LR6 CR0 ;;
block:
    SUB LR2 LR5 CR1 ; {{ coeff_load() }}{% if k > 128 %} ; SET LR7 {{ cr.full_chunks }}{% endif %} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {{ coeff_load() }} ;;
{% if k > 128 %}
{{ chunk('full', 128, ' ; DEC LR7 1 ; BNE LR7 CR1 next_full') }}
    {{ coeff_load() }} ; B tail_load ;;
next_full:
    {{ coeff_load() }} ; B full_load ;;
{% endif %}
{{ chunk('tail', (k - 1) % 128 + 1) }}
{% if n > 128 %}
    BLT.S LR6 {{ cr.last }} store_full ;;
{% endif %}
    {{ store(cr.tail_ds) }} ; ADD LR5 LR5 {{ cr.chunks }} ;;
    BLT.S LR5 {{ cr.in_rows }} pixel ;;
    HALT ;;
{% if n > 128 %}
store_full:
    {{ store(cr.full_ds) }} ; INC LR6 1 ; B block ;;
{% endif %}
{% endif %}
