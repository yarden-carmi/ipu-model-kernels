{% macro reduce(index, first) %}
    MULT.RC.VE {{ index }} CR1 0 LR0 {{ cr.pair }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ '.FIRST' if first else '' }} LR4 {{ cr.pair }}.L
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 {{ cr.slot128 }} ;;
    SET LR7 CR0 ; SET LR9 CR0 ; SET LR10 {{ cr.slot128 }} ;;
{% if in0_d1 > 1 %}
    SET LR11 CR0 ;;
    DEC LR11 1 ;;
{% endif %}
{# Reduce directly from two input rows into the output channel lane. #}
pixel:
    SET LR4 {{ 'LR11' if in0_d1 > 1 else 'CR0' }} ; SET LR1 LR7 ; LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
{% if in0_d1 > 1 %}
    {# Load the other row or the next channel while consuming the previous load. #}
channel:
    {{ reduce('LR9', true) }} ; INC LR4 1 ; INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR3 ;;
    {{ reduce('LR10', false) }} ; ADD LR1 LR1 {{ cr.channel_gap }} ; LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ; BLT.S LR4 LR14 channel ;;
{% endif %}
    {{ reduce('LR9', true) }} ; {% if in0_d1 > 1 %}INC LR4 1 ; {% endif %}INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR3 ;;
    {{ reduce('LR10', false) }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR9 2 ; INC LR10 2 ; BLT.S LR9 LR13 pixel ;;
    INC LR7 2 ; SET LR9 CR0 ; SET LR10 {{ cr.slot128 }} ; BLT.S LR7 LR12 pixel ;;
    HALT ;;
