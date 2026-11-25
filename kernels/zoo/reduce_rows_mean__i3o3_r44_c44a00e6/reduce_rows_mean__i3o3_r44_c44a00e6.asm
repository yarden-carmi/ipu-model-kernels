{# Reduce spatial lanes directly into the sole active output lane. #}
{% set inv = 'CR1' if format == 'fp32' else cr.inv %}
{% macro accumulate(op, ds) %}
    MULT.VE LR0 {{ inv }} 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; {{ op }} LR0 {{ ds }}.L ;;
{% endmacro %}
{% macro advance(label) %}
    BLT.S LR4 {{ cr.width }} {{ label }} ;;
    INC LR1 1 ; SET LR4 CR0 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
{{ label }}:
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
{% if format == 'fp32' %}
    INC LR8 8 ; INC LR9 32 ; INC LR10 128 ;;
{% endif %}
channel:
{% if format == 'fp32' %}
    BEQ LR8 {{ cr.left }} ordinary ;;
    BLT.S LR8 {{ cr.left }} ordinary ;;
    BEQ LR0 {{ cr.groups }} ordinary ;;
    SET LR4 CR0 ; SET LR5 {{ cr.groups }} ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
vector_groups:
    SET LR6 CR0 ; DEC LR5 1 ;;
vector_element:
    {{ advance('vector_loaded') }}
    MULT.EE LR4 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ cr.one }}.L ;;
    INC LR4 1 ; INC LR6 1 ;;
    BLT.S LR6 LR9 vector_element ;;
    BNE LR5 CR0 vector_groups ;;
    ACTIVATE.QUANTIZE identity {{ cr.one }}.H {{ cr.qf_out0 }}.L {{ cr.sum_row }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.sum_row }} ; SET LR5 {{ cr.left }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    BEQ LR5 CR0 horizontal ;;
scalar_tail:
    {{ advance('tail_loaded') }}
    MULT.EE LR4 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 {{ cr.one }}.L ; DEC LR5 1 ;;
    INC LR4 1 ; BNE LR5 CR0 scalar_tail ;;
horizontal:
    INC LR1 1 ;;
    SET LR4 CR0 ;;
horizontal_lane:
    ADD LR5 LR4 LR10 ;;
    {% for group in range(4) %}
    MULT.EE LR5 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; {{ 'AGG.SUM.FIRST' if group == 0 else 'AGG.SUM' }} LR8 {{ cr.one }}.L ;;
    {% if not loop.last %}INC LR5 8 ;;{% endif %}
    {% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.one }}.H {{ cr.qf_out0 }}.L {{ cr.sum_row }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.sum_row }} ;;
    MULT.EE LR8 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; AGG.SUM LR0 {{ cr.one }}.L ; INC LR4 1 ;;
    BLT.S LR4 LR8 horizontal_lane ;;
    BEQ LR0 CR0 store ;;
ordinary:
{% endif %}
    SET LR3 {{ cr.spatial }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
remaining:
    LD.MULT R0 LR1 {{ cr.in0 }} ; DEC LR3 1 ;;
    {{ accumulate('AGG.SUM', cr.active) }}
    INC LR1 1 ; BNE LR3 CR0 remaining ;;
store:
{% if format == 'fp32' %}
    ACTIVATE.QUANTIZE identity {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.sum_row }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.sum_row }} ;;
    MULT.VE LR0 {{ cr.inv_fp32 }} 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.out0_d1 }} channel ;;
    HALT ;;
