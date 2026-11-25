{# Reduce four adjacent lanes of each cyclic scanline into one output lane. #}
{% macro scanline(slot, first, last) %}
    MULT.RC.VE {{ slot }} {{ cr.weight_fp32 if format == 'fp32' else cr.weight }} 0 LR12 {{ cr.reduce_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR6 {{ cr.reduce_ds }}.L ;;
    INC {{ slot }} 2 {% if last %}; INC LR6 1 {% endif %} ;;
{% endmacro %}
{% macro load_line(slot, last) %}
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} {{ slot }} ;;
    {% if not last %} INC LR5 1 ;; {% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR7 CR0 ;;
    SET LR12 CR0 ;;
batch:
    SET LR1 CR0 ;;
out_y:
    SET LR4 LR3 ; SET LR2 CR0 ;;
plane:
    SET LR5 LR4 ; SET LR6 CR0 ; SET LR8 CR0 ;;
    SET LR9 LR13 ; SET LR10 LR14 ; SET LR11 LR15 ;;
{% for i in range(4) %}
    {{ load_line('LR' ~ (8+i), i == 3) }}
{% endfor %}
out_x:
{% for i in range(4) %}
    {{ scanline('LR' ~ (8+i), i == 0, i == 3) }}
{% endfor %}
    BLT.S LR6 {{ cr.out0_d3 }} out_x ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.store_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR2 1 ; ADD LR4 LR4 {{ cr.in0_d2 }} ;;
    BLT.S LR2 {{ cr.out0_d1 }} plane ;;
    INC LR1 1 ;;
    BGE.S LR1 {{ cr.out0_d2 }} next_batch ;;
    INC LR3 2 ;;
    BEQ LR12 CR0 out_y ;;
next_batch:
    ADD LR3 LR3 {{ cr.batch_jump }} ; INC LR0 1 ;;
    BLT.S LR0 {{ cr.out0_d0 }} batch ;;
    HALT ;;
