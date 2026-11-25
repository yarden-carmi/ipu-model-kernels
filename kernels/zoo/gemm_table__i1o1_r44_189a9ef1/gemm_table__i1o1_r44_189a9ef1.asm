{# Keep a pixel's input channels in R0 while streaming output-channel vectors. #}
{% macro next_coeff() -%}
INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, first=false) -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro pair(next=true, branch='') -%}
    {{ mac('LR5') }} ; INC LR7 1 ; {{ next_coeff() }} ;;
    {{ mac('LR7') }} ; INC LR5 1{% if next %} ; {{ next_coeff() }}{% endif %}{{ branch }} ;;
{%- endmacro %}
{% macro chunk(size, label, limit, more=false) %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR5 CR0 ; SET LR7 CR0 ;;
    DEC LR7 1 ;;
{% if size > 8 %}
{{ label }}:
{% for j in range(8) %}
    {{ pair(true, ' ; BNE LR5 ' ~ limit ~ ' ' ~ label if loop.last else '') }}
{% endfor %}
{% endif %}
{% for j in range(1 + (size - 1) % 8) %}
    {{ pair(more or not loop.last) }}
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR1 CR0 ; DEC LR2 1 ;;
{% for j in range(5) %}
    {% if j %}INC LR1 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR1 ;;
{% endfor %}
{% if k > 128 %}
    SET LR10 CR0 ;;
    INC LR10 119 ;;
{% endif %}
pixel:
    SET LR4 CR0 ; SET LR9 {{ cr.blocks }} ;;
    DEC LR4 1 ;;
tile:
    {{ next_coeff() }} ; SET LR6 LR3 ; DEC LR9 1 ;;
    {{ mac('CR1', true) }} ; {{ next_coeff() }} ; SET LR8 {{ cr.preceding }} ;;
    {{ mac('CR1') }} ; {{ next_coeff() }} ;;
{% if k > 128 %}
full_chunk:
{{ chunk(128, 'full_group', 'LR10', true) }}
    INC LR6 1 ; DEC LR8 1 ; BNE LR8 CR1 full_chunk ;;
{% endif %}
{{ chunk(1 + (k - 1) % 128, 'tail_group', cr.group_limit) }}
{% if n > 128 and n % 128 %}
    BNE LR9 CR0 full_store ;;
{% endif %}
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2{% if n > 128 and not n % 128 %} ; BNE LR9 CR0 tile{% endif %} ;;
    ADD LR3 LR3 {{ cr.chunks }} ;;
    BNE LR3 {{ cr.input_rows }} pixel ;;
    HALT ;;
{% if n > 128 and n % 128 %}
full_store:
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.full_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; B tile ;;
{% endif %}
