{% macro rhs(start, acc='ACC.ADD') %}
    MULT.VE {{ start }} CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in1 }}.L ; {{ acc }}
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
pair:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR10 CR0 ;;
pixel:
    SET LR6 LR5 ; SET LR7 CR0 ;;
channel:
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR7 1 ;;
    // Scatter the selected spatial lane to this channel in the packed row.
    MULT.EE LR4 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR6 1 ;;
    ADDBI LRD2 1 ; BNE LR7 {{ cr.in0_d1 }} channel ;;

    INC LR9 1 ; INC LR4 1 ;;
    BNE LR4 {{ cr.in0_d3 }} next_pixel ;;
    SET LR4 CR0 ; ADD LR5 LR5 {{ cr.in0_d1 }} ;;
next_pixel:
    BNE LR10 CR0 full ;;
    BEQ LR9 {{ cr.pixels }} tail ; SET LR10 CR1 ;;
    B pixel ;;
full:
    SUB LR12 LR9 CR1 ;;
    SUB LR13 LR12 CR1 ;;
    LD.MULT R0 LR13 {{ cr.in1 }} ;;
    {{ rhs('LR0') }} ; LD.MULT R1 LR12 {{ cr.in1 }} ;;
    {{ rhs('LR11') }} ; {{ store('L') }} ;;
    INC LR8 1 ; BNE LR9 {{ cr.pixels }} pair ;;
    HALT ;;
tail:
    SUB LR12 LR9 CR1 ;;
    LD.MULT R0 LR12 {{ cr.in1 }} ;;
    {{ rhs('LR0') }} ; {{ store('H') }} ;;
    HALT ;;
