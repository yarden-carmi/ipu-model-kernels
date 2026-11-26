{% macro pixel(first, advance) %}
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.VE LR0 {{ cr.weight_fp32 if format == 'fp32' else cr.weight }} 0 LR0 {{ cr.input_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} {% if advance %}; INC LR6 1 {% endif %} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
batch:
    SET LR3 CR0 ; SET LR4 CR0 ;;
out_y:
    SET LR5 LR1 ; SET LR7 CR0 ;;
out_x:
    SET LR8 LR5 ;;
{% for y in range(4) %}
    SET LR6 LR8 ;;
{% for x in range(4) %}
    {{ pixel(y == 0 and x == 0, x != 3) }}
{% endfor %}
{% if y != 3 %}
    ADD LR8 LR8 {{ cr.w }} ;;
{% endif %}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.input_ds }}.L {{ cr.qf_out0 }}.L {{ cr.pooled }} LR3 ;;
    INC LR3 1 ; INC LR5 2 ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.out0_d3 }} out_x ;;
    ADD LR1 LR1 {{ cr.w }} ; INC LR4 1 ;;
    ADD LR1 LR1 {{ cr.w }} ;;
    BLT.S LR4 {{ cr.out0_d2 }} out_y ;;
    ADD LR1 LR1 LR15 ; SET LR10 CR0 ; SET LR11 CR0 ;;
    SET LR5 CR0 ;;
channel:
    SET LR3 CR0 ;;
packed_row:
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR4 LR14 ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.input_ds }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
gather:
    LD.MULT R0 LR3 {{ cr.pooled }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.input_ds }}.L {{ cr.qf_out0 }}.L ; ACC.RESHAPE LRD10 LRD8 7 ;;
    ADDBI LRD8 1 ; DEC LR4 1 ; INC LR3 1 ;;
    BEQ LR3 LR13 last_store ;;
    BNE LR4 CR0 gather ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.output_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; B packed_row ;;
last_store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.last_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    ADDBI LRD10 1 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.out0_d1 }} channel ;;
    BLT.S LR1 LR12 batch ;;
    HALT ;;
