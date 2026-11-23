{# Transpose one pixel at a time, stepping by one channel plane in memory. #}
{% set route_scale = 'CR1' if format == 'fp32' else cr.route_control %}
    SET LR0 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
pack_row:
    SET LR7 CR0 ;;
route_pixel:
    SET LR3 CR0 ; SET LR5 CR0 ; SET LR6 LR9 ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.valid }}.H {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
route_channel:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.VE LR7 {{ route_scale }} 0 LR0 {{ cr.valid }}.H {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 7 ;;
    ADDBI LRD4 1 ; ADD LR6 LR6 LR11 ;;
    BLT.S LR6 LR12 route_channel ;;
    ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf_in0 }}.L {{ cr.routed }} LR8 ;;
    INC LR8 1 ; INC LR7 1 ;;
    BLT.S LR7 LR14 route_pixel ;;
    INC LR9 1 ;;
    BLT.S LR9 LR11 pack_row ;;

{# The cascade reduces to [3/4,1/4] on each axis. #}
{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% macro term(idx, weight, first=false) %}
    MULT.RC.VE {{ idx }} {{ weight }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
{% macro pixel() %}
    LD.MULT.CYCLIC LR8 {{ cr.routed }} LR2 ;;
    LD.MULT.CYCLIC LR9 {{ cr.routed }} LR3 ;;
    {{ term('LR3', w1, true) }}
    {{ term('LR2', w3) }}
    {{ term('LR1', w3) }}
    {{ term('LR0', w9) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ;;
{% endmacro %}
    SET LR4 CR0 ; SET LR12 CR0 ; SET LR11 CR0 ;;
    SET LR1 CR0 ;;
    INC LR1 128 ;;
    ADD LR2 LR1 LR1 ;;
    ADD LR3 LR2 LR1 ;;
y:
    SUB LR5 LR4 {{ cr.in0_d3 }} ; SET LR13 CR0 ; BNE LR11 CR0 scan ;;
    SET LR5 LR4 ;;
scan:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR10 CR0 ;;
x:
    LD.MULT.CYCLIC LR6 {{ cr.routed }} LR0 ; SUB LR8 LR6 CR1 ; SUB LR9 LR7 CR1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.routed }} LR1 ; BNE LR10 CR0 left ;;
    SET LR8 LR6 ; SET LR9 LR7 ;;
left:
    {{ pixel() }}
    INC LR10 1 ; ADD LR8 LR6 CR1 ; ADD LR9 LR7 CR1 ;;
    BLT.S LR10 {{ cr.in0_d3 }} right ;;
    SET LR8 LR6 ; SET LR9 LR7 ;;
right:
    {{ pixel() }}
    INC LR6 1 ; INC LR7 1 ; BLT.S LR10 {{ cr.in0_d3 }} x ;;
    BNE LR13 CR0 next_y ;;
    INC LR13 1 ; ADD LR5 LR4 {{ cr.in0_d3 }} ; INC LR11 1 ;;
    BLT.S LR11 LR15 scan ;;
    SET LR5 LR4 ; B scan ;;
next_y:
    ADD LR4 LR4 {{ cr.in0_d3 }} ; BLT.S LR11 LR15 y ;;
    HALT ;;
