{% set ds = cr.valid ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro coefficient(src, op='ADD') %}
    LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR0 ;;
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qi }} ; ACC.{{ op }} ; INC LR7 1 ;;
{% endmacro %}
{% macro phase(id, offset) %}
    ADD LR3 LR2 CR0 ; ADD LR8 LR7 {{ cr.phase_rows }} ; ADD LR6 LR5 {{ offset }} ;;
    {{ coefficient('CR1','ADD.FIRST') }}
    {{ coefficient('CR1') }}
dot_{{ id }}:
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
    {{ coefficient('LR1') }}
    {{ coefficient('LR1') }}
    ADD LR3 LR3 {{ cr.channel_rows }} ; BLT.S LR7 LR8 dot_{{ id }} ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
{% endmacro %}
{# LR1/LR2 identify the packed spatial position of channel zero.
   LR5 is the top-left output of the current 2x2 tile. #}
pixel:
    SET LR7 CR0 ;;
    {{ phase(0,'CR0') }}
    {{ phase(1,'CR1') }}
    {{ phase(2,cr.out0_d3) }}
    INC LR6 1 ;;
    {# Use the previous phase's address plus one for bottom-right. #}
    SUB LR12 LR6 LR5 ;;
    {{ phase(3,'LR12') }}
    INC LR5 2 ; INC LR1 1 ; INC LR9 1 ;;
    BLT.S LR1 {{ cr.lane_limit }} packed ;;
    SET LR1 CR0 ; INC LR2 1 ;;
packed:
    BLT.S LR9 {{ cr.w }} pixel ;;
    SET LR9 CR0 ; ADD LR5 LR5 {{ cr.out0_d3 }} ; INC LR10 1 ;;
    INC LR11 1 ; BGE.S LR10 {{ cr.total_y }} finished ;;
    BLT.S LR11 {{ cr.h }} pixel ;;
    SET LR11 CR0 ; ADD LR2 LR2 {{ cr.batch_skip }} ;;
    BNE CR0 CR1 pixel ;;
finished:
    HALT ;;
