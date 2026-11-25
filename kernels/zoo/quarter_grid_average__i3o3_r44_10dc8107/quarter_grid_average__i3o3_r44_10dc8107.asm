{# Each reduction writes one lane of the eventual packed output row. #}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
{% endmacro %}
{% macro scanline(slot, first, last) %}
    MULT.RC.VE {{ slot }} {{ cr.weight_fp32 if format == 'fp32' else cr.weight }} 0 LR14 {{ cr.reduce_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR6 {{ cr.reduce_ds }}.L ;;
    INC {{ slot }} 2 {% if last %}; INC LR6 1 ; INC LR12 1 {% endif %} ;;
{% endmacro %}
{% macro load_line(slot, last) %}
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} {{ slot }} ;;
    {% if not last %} INC LR5 1 ;; {% endif %}
{% endmacro %}

    SET LR14 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ;;
plane:
    SET LR4 LR1 ; SET LR2 CR0 ;;
out_y:
    SET LR5 LR4 ; SET LR8 CR0 ; SET LR9 LR13 ;;
    ADD LR10 LR13 LR13 ; SET LR11 LR15 ; SET LR12 CR0 ;;
{% for i in range(4) %}
    {{ load_line('LR' ~ (8+i), i == 3) }}
{% endfor %}
out_x:
{% for i in range(4) %}
    {{ scanline('LR' ~ (8+i), i == 0, i == 3) }}
{% endfor %}
    BLT.S LR12 {{ cr.out0_d3 }} out_x ;;
    BNE LR6 {{ cr.packed_width }} advance ;;
    {{ store(cr.store_ds) }}
    SET LR6 CR0 ; INC LR7 1 ;;
advance:
    INC LR4 2 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.out0_d2 }} out_y ;;
    ADD LR1 LR1 {{ cr.in0_d2 }} ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.planes }} plane ;;
    BEQ LR6 CR0 finish ;;
    {{ store(cr.tail_ds) }}
finish:
    HALT ;;
