{% macro add_and_store(half) %}
    LD.MULT R0 LR8 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds_pair }}.{{ half }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
pair:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR10 CR0 ;;
pixel:
    SET LR6 LR5 ; SET LR7 CR0 ;;
channel:
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR7 1 ;;
    // Broadcast just this pixel of the current channel, then place it in
    // the packed output accumulator. No intermediate NX8 quantization.
    MULT.EE LR4 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR6 LR6 {{ cr.channel_stride }} ;;
    ADDBI LRD2 1 ; BNE LR7 {{ cr.out0_d1 }} channel ;;

    INC LR9 1 ; INC LR4 1 ;;
    BNE LR4 {{ cr.spatial_lanes }} pixel_done ;;
    SET LR4 CR0 ; INC LR5 1 ;;
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
