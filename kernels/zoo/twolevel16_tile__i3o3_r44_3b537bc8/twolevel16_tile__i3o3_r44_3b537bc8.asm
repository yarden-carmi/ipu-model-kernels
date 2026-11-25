{% set ds = cr.valid ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}

{# Expand packed input rows to [x0,x0,x1,x1,...] once. #}
pack_load:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ; SET LR2 CR0 ;;
    INC LR1 1 ;;
duplicate_row:
    SET LR4 LR12 ; SET LR5 LR13 ; SET LR6 LR14 ;;
    SET LR7 LR15 ; SET LR8 CR0 ;;
duplicate_chunk:
    MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD4 LRD6 0 ;;
    ADDBI LRD6 1 ;;
    MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD4 LRD6 0 ;;
    ADDBI LRD4 8 ; ADDBI LRD6 15 ; INC LR8 8 ;;
    BLT.S LR8 {{ cr.in0_d3 }} duplicate_chunk ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.duplicated }} LR3 ;;
    INC LR3 1 ; ADD LR2 LR2 {{ cr.in0_d3 }} ;;
    BLT.S LR2 {{ cr.packed_width }} duplicate_row ;;
    BLT.S LR3 {{ cr.total_input_rows }} pack_load ;;

{# A dot writes one vertical phase; LR7 advances into the next phase. #}
{% macro project(phase) %}
    SET LR3 LR2 ; ADD LR9 LR7 {{ cr.phase_rows }} ;;
    LD.MULT R0 LR7 {{ cr.coeff }} ;;
    LD.MULT R0 LR7 {{ cr.coeff }} ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR7 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR7 1 ;;
dot_{{ phase }}:
    LD.MULT.CYCLIC LR3 {{ cr.duplicated }} LR0 ;;
    LD.MULT R0 LR7 {{ cr.coeff }} ; ADD LR3 LR3 {{ cr.in0_d2 }} ;;
    LD.MULT R0 LR7 {{ cr.coeff }} ; MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR7 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR7 1 ;;
    BLT.S LR7 LR9 dot_{{ phase }} ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endmacro %}

    SET LR4 CR0 ; SET LR6 CR0 ;;
channel:
    SET LR1 CR0 ;;
batch:
    SET LR2 LR1 ; SET LR8 CR0 ;;
spatial_row:
    SET LR7 LR6 ;;
    {{ project('top') }}
    {{ project('bottom') }}
    INC LR2 1 ; INC LR8 1 ;;
    BLT.S LR8 {{ cr.in0_d2 }} spatial_row ;;
    ADD LR1 LR1 {{ cr.batch_rows }} ;;
    BLT.S LR1 {{ cr.total_input_rows }} batch ;;
    SET LR6 LR7 ;;
    BLT.S LR6 {{ cr.coeff_end }} channel ;;
    HALT ;;
