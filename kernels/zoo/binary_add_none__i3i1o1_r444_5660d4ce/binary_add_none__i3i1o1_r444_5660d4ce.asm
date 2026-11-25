{% macro add_and_store(half) %}
    LD.MULT R0 LR8 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds_pair }}.{{ half }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ;;
pair:
    SUB LR3 LR0 CR1 ; SET LR10 CR0 ;;
pixel:
    // Each source row holds one channel. Place its selected column
    // directly in the output accumulator, without quantizing the transpose.
    SET LR6 LR5 ; ADD LR7 LR5 {{ cr.in0_d1 }} ;;
channel:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.ds_one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.ds_one }}.L ; INC LR3 1 ;;
    INC LR6 1 ;;
    BNE LR6 LR7 channel ;;
    INC LR9 1 ; INC LR4 1 ;;
    BNE LR4 {{ cr.in0_d3 }} pixel_done ;;
    SET LR4 CR0 ; ADD LR5 LR5 {{ cr.in0_d1 }} ;;
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
