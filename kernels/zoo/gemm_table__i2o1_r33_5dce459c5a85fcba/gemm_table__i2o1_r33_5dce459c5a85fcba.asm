{% macro tile(label, count, ds) %}
    SUB LR5 LR0 CR1 ; SET LR6 {{ count }} ; DEC LR11 1 ;;
{{ label }}_token:
    INC LR5 1 ; LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ;;
{% if k > 128 %}
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR5 {{ cr.full_ds }}.L ; INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ;;
{% endif %}
    MULT.RC.VV LR0 {{ 'R1' if k > 128 else 'R0' }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{% if k <= 128 %}.FIRST{% endif %} LR5 {{ cr.full_ds }}.L ; INC LR3 1{% if not bias %} ; DEC LR6 1 ; BNE LR6 CR0 {{ label }}_token{% endif %} ;;
{% if bias %}
    MULT.RC.VE LR14 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 {{ cr.one_ds }}.L ; DEC LR6 1 ; BNE LR6 CR0 {{ label }}_token ;;
{% endif %}
    INC LR7 1 ; ACTIVATE.QUANTIZE {{ 'generic' if act_out0 else 'identity' }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR8 CR0 ;;
    SUB LR7 LR0 CR1 ; SET LR14 CR0 ;;
    INC LR14 128 ;;
    INC LR14 128 ;;
{% for j in range(5) %}
    {% if j %}INC LR1 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR1 ;;
{% endfor %}
batch:
    SET LR4 CR0 ; SET LR9 CR0 ; SET LR10 {{ cr.n }} ;;
channel:
    SET LR3 LR8 ; SET LR11 {{ cr.tiles }} ; LD.MULT R0 LR4 {{ cr.w }} ;;
{% if k > 128 %}
    INC LR4 1 ; LD.MULT R1 LR4 {{ cr.w }} ;;
{% endif %}
    INC LR4 1 ; DEC LR10 1 ; SUB LR11 LR11 CR1{% if bias %} ; LD.MULT.CYCLIC LR9 {{ cr.b }} LR14{% endif %} ;;
    BEQ LR11 CR0 tail ;;
full:
    {{ tile('full', cr.full_count, cr.full_ds) }}
    BNE LR11 CR0 full ;;
tail:
    {{ tile('tail', cr.tail_count, cr.tail_ds) }}
    INC LR9 1 ; BNE LR10 CR0 channel ;;
    SET LR8 LR3 ; DEC LR15 1 ; BNE LR15 CR1 batch ;;
    HALT ;;
