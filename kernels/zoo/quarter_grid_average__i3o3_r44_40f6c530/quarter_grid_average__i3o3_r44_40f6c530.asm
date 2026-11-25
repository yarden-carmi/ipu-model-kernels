{# Four source rows stay in the cyclic buffer while walking the output width.
   Each aggregate sums four adjacent taps directly into its packed output lane. #}
{% macro load_row(slot, advance) %}
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} {{ slot }} {% if advance %}; INC LR5 1 {% endif %};;
{% endmacro %}
{% macro taps(i) %}
    MULT.RC.VE LR{{ 8 + i }} {{ cr.weight_fp32 if format == 'fp32' else cr.weight }} 0 LR12 {{ cr.horizontal4 }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if i == 0 else '' }} LR4 {{ cr.horizontal4 }}.L ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; SET LR4 CR0 ;;
    INC LR3 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ; SET LR12 CR0 ;;
plane:
    SET LR2 LR1 ; SET LR6 CR0 ;;
line:
    SET LR5 LR2 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR9 LR13 ; SET LR10 LR14 ; SET LR11 LR15 ;;
{% for slot in ['LR12', 'LR13', 'LR14', 'LR15'] %}
    {{ load_row(slot, not loop.first) }}
{% endfor %}
pixel:
{% for i in range(4) %}
    {{ taps(i) }}
{% endfor %}
    INC LR4 1 ; INC LR7 1 ; INC LR8 2 ;;
    INC LR9 2 ; INC LR10 2 ; INC LR11 2 ; BLT.S LR7 {{ cr.out0_d3 }} pixel ;;
    BLT.S LR4 {{ cr.packed_lanes }} next_line ;;
    {{ store(cr.full) }}
next_line:
    INC LR2 2 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.out0_d2 }} line ;;
    ADD LR1 LR1 {{ cr.image_rows }} ; INC LR0 1 ;;
    BLT.S LR0 {{ cr.planes }} plane ;;
    BEQ LR4 CR0 done ;;
    {{ store(cr.tail) }}
done:
    HALT ;;
