{# Each vector holds one feature for up to 128 samples. The coefficient
   stream is packed by output channel, with a separate bias row. #}
{% macro chunk(count, label) %}
    LD.MULT R0 LR5 {{ cr.coeff }} ; SET LR6 CR0 ; SET LR7 CR0 ;;
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; INC LR5 1 ; DEC LR6 1 {% if count > 3 %}; INC LR7 {{ count - 3 }} {% elif count == 2 %}; DEC LR7 1 {% endif %} ;;
{% if count > 1 %}
{{ label }}:
    {{ mac() }} ; LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; BLT.S LR6 LR7 {{ label }} ;;
{% endif %}
    {{ mac() }} ;;
{% endmacro %}
{% macro mac() %}
    MULT.RC.VE LR0 LR6 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR6 1 ; ADD LR4 LR4 {{ cr.blocks }}
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; INC LR9 1
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR9 CR0 ;;
    DEC LR9 1 ; SET LR13 CR0 ; SET LR14 {{ cr.in0_d0 }} ;;
{% for i in range(5) %}
    {% if i %}INC LR1 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
{% endfor %}
batch:
    SET LR2 CR0 ; SET LR10 {{ cr.n }} ;;
channel:
    SET LR11 LR13 ; SET LR12 {{ cr.blocks }} ;;
block:
    ADD LR3 LR2 {{ cr.chunks }} ;;
    ADD LR15 LR3 {{ cr.chunks }} ;;
    INC LR15 1 ;;
    LD.MULT R0 LR3 {{ cr.coeff }} ; SET LR4 LR11 ; SET LR5 LR2 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR15 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% if k > 128 %}
    SET LR8 {{ cr.groups }} ;;
groups:
    {{ chunk(128, 'reduce_full') }}
    DEC LR8 1 ; BNE LR8 CR1 groups ;;
{% endif %}
    {{ chunk((k - 1) % 128 + 1, 'reduce_last') }}
    SET LR4 LR11 ; SET LR5 LR3 ;;
    INC LR5 1 ;;
{% if k > 128 %}
    SET LR8 {{ cr.groups }} ;;
groups_residual:
    {{ chunk(128, 'reduce_full_residual') }}
    DEC LR8 1 ; BNE LR8 CR1 groups_residual ;;
{% endif %}
    {{ chunk((k - 1) % 128 + 1, 'reduce_last_residual') }}
    SET LR3 LR15 ;;
    ADD LR15 LR3 {{ cr.chunks }} ;;
    INC LR15 1 ;;
    LD.MULT R0 LR15 {{ cr.coeff }} ; SET LR4 LR11 ; SET LR5 LR3 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR5 1 ;;
{% if k > 128 %}
    SET LR8 {{ cr.groups }} ;;
groups_third:
    {{ chunk(128, 'reduce_full_third') }}
    DEC LR8 1 ; BNE LR8 CR1 groups_third ;;
{% endif %}
    {{ chunk((k - 1) % 128 + 1, 'reduce_last_third') }}
    DEC LR12 1 ; INC LR11 1 ; BNE LR12 CR1 full_block ;;
    {{ store(cr.tail) }} ;;
    SET LR2 LR15 ; DEC LR10 1 ; BNE LR10 CR1 next_channel ;;
    ADD LR13 LR13 {{ cr.batch_rows }} ; DEC LR14 1 ; BNE LR14 CR1 batch ;;
    HALT ;;
full_block:
    {{ store(cr.full) }} ; B block ;;
next_channel:
    INC LR2 1 ; B channel ;;
