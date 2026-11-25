{% set ds = cr.valid ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}

{# Both vertical phases get the same horizontally duplicated input. #}
{% macro duplicate(label, lo, hi) %}
    SET LR4 LR12 ; SET LR5 LR13 ; SET LR6 {{ lo }} ;;
    SET LR7 {{ hi }} ; SET LR8 CR0 ;;
duplicate_{{ label }}:
    MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD4 LRD6 0 ;;
    ADDBI LRD6 1 ;;
    MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD4 LRD6 0 ;;
    ADDBI LRD4 8 ; ADDBI LRD6 15 ; INC LR8 8 ;;
    BLT.S LR8 {{ cr.in0_d3 }} duplicate_{{ label }} ;;
{% endmacro %}

pack_load:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ; SET LR2 CR0 ;;
    INC LR1 1 ;;
duplicate_row:
    MULT.RC.VE LR2 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
    {{ duplicate('top', 'LR14', 'LR15') }}
    {{ duplicate('bottom', 'LR10', 'LR11') }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.duplicated }} LR3 ;;
    INC LR3 1 ; ADD LR2 LR2 {{ cr.in0_d3 }} ;;
    BLT.S LR2 {{ cr.packed_width }} duplicate_row ;;
    BLT.S LR3 {{ cr.total_input_rows }} pack_load ;;

    SET LR1 CR0 ; SET LR4 CR0 ;;
batch:
    SET LR6 CR0 ;;
channel:
    SET LR2 LR1 ; SET LR8 CR0 ; ADD LR9 LR6 {{ cr.channel_rows }} ;;
spatial_row:
    SET LR7 LR6 ; SET LR3 LR2 ;;
    LD.MULT R0 LR7 {{ cr.coeff }} ;;
    LD.MULT R0 LR7 {{ cr.coeff }} ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR7 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR7 1 ;;
dot:
    LD.MULT.CYCLIC LR3 {{ cr.duplicated }} LR0 ;;
    LD.MULT R0 LR7 {{ cr.coeff }} ; ADD LR3 LR3 {{ cr.in0_d2 }} ;;
    LD.MULT R0 LR7 {{ cr.coeff }} ; MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR7 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR7 1 ;;
    BLT.S LR7 LR9 dot ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; INC LR2 1 ; INC LR8 1 ;;
    BLT.S LR8 {{ cr.in0_d2 }} spatial_row ;;
    SET LR6 LR9 ;;
    BLT.S LR6 {{ cr.coeff_end }} channel ;;
    ADD LR1 LR1 {{ cr.batch_rows }} ;;
    BLT.S LR1 {{ cr.total_input_rows }} batch ;;
    HALT ;;
