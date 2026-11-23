{# One accumulator lane per output channel of the current spatial row. #}
{% macro dot(ds, last='') %}
    LD.MULT.CYCLIC LR3 {{ cr.coeff }} LR0 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR3 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ ds }}.L ; INC LR4 1 ;;
    LD.MULT.CYCLIC LR3 {{ cr.coeff }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ ds }}.L ; INC LR3 1 ;;
    {{ last }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR5 {{ cr.m }} ;;
pixel:
    SET LR3 CR0 ; SET LR6 CR0 ; SET LR8 CR0 ;;
{% if tiles > 1 %}
    INC LR8 {{ tiles }} ;;
    SET LR7 CR0 ;;
    INC LR7 128 ;;
{% endif %}
{% if n > 1 %}
    SET LR10 CR0 ;;
    INC LR10 {{ (n - 1) % 128 + 1 }} ;;
{% endif %}
channel:
    LD.MULT R0 LR3 {{ cr.coeff }} ; SET LR4 LR1 ; SET LR9 {{ cr.full_chunks }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_coeff }}.L ; AGG.SUM.FIRST LR6 {{ cr.one }}.L ; INC LR3 1 ;;
{% if chunks > 1 %}
chunk:
    {{ dot(cr.full, 'DEC LR9 1') }}
    BNE LR9 CR0 chunk ;;
{% endif %}
    {{ dot(cr.tail_k, 'INC LR6 1') }}
{% if tiles > 1 %}
    BEQ LR8 CR1 tail ;;
    BLT.S LR6 LR7 channel ;;
    {{ store(cr.full) }} ;;
    INC LR2 1 ; DEC LR8 1 ; SET LR6 CR0 ; BEQ CR0 CR0 channel ;;
tail:
{% endif %}
    {% if n > 1 %}
    BLT.S LR6 LR10 channel ;;
    {% endif %}
    {{ store(cr.tail_n) }} ;;
    INC LR2 1 ; ADD LR1 LR1 {{ cr.in_pitch }} ; DEC LR5 1 ;;
    BNE LR5 CR0 pixel ;;
    HALT ;;
