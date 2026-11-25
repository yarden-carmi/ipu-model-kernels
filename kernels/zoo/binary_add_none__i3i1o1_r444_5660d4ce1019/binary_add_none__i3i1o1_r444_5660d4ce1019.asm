{% macro add_and_store(half) %}
    LD.MULT R0 LR8 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds_pair }}.{{ half }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
pair:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR10 CR0 ;;
pixel:
    SET LR6 LR5 ; ADD LR7 LR5 {{ cr.out0_d1 }} ;;
channel:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    // Select width lane LR4 and scatter it to the next packed channel.
    MULT.EE LR4 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR6 1 ;;
    ADDBI LRD2 1 ; BNE LR6 LR7 channel ;;

    INC LR9 1 ; INC LR4 1 ;;
    BNE LR4 {{ cr.in0_d3 }} pixel_done ;;
    SET LR4 CR0 ; SET LR5 LR7 ;;
pixel_done:
    BNE LR10 CR0 store_pair ;;
    BEQ LR9 {{ cr.pixels }} tail ; SET LR10 CR1 ;;
    B pixel ;;
store_pair:
    {{ add_and_store('L') }}
    INC LR8 1 ; BNE LR9 {{ cr.pixels }} pair ;;
    HALT ;;
tail:
    {{ add_and_store('H') }}
    HALT ;;
