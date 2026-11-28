{% macro loadcoef() %}LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    SET LR9 {{ cr.n }} ; DEC LR3 1 ;;
    SET LR10 CR0 ; SET LR11 {{ cr.startlane }} ;;
    INC LR10 128 ;;
channel:
    SET LR6 CR0 ; SET LR7 {{ cr.tiles }} ;;
tile:
    SET LR8 LR5 ; SET LR4 {{ cr.k }} ;;
    ADD LR2 LR6 {{ cr.startrow }} ; DEC LR8 1 ;;
    {{ loadcoef() }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ loadcoef() }} ;;
{% if m <= 128 and (in0_d1 - m) % 128 != 0 and ((in0_d1 - m) // 128 + 1) < ((in0_d1 + 127) // 128) %}
    DEC LR2 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; INC LR2 1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR10 ; INC LR2 1 ;;
    {{ loadcoef() }} ;;
fast_reduce:
    MULT.RC.VV LR11 R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef() }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR4 1 ;;
    BEQ LR4 CR0 fast_finish ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.stride_minus_one }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR10 ; INC LR2 1 ;;
    {{ loadcoef() }} ; B fast_reduce ;;
fast_finish:
{% else %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
reduce:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    INC LR2 1 ;;
{% if (in0_d1 - m) % 128 != 0 %}
    ADD LR12 LR6 {{ cr.startrow }} ;;
    INC LR12 1 ;;
    BEQ LR12 {{ cr.stride }} no_second ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR10 ;;
no_second:
{% endif %}
    DEC LR2 1 ; {{ loadcoef() }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef() }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR2 LR2 {{ cr.stride }} ; DEC LR4 1 ;;
    BNE LR4 CR0 reduce ;;
{% endif %}
    BEQ LR7 CR1 last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; INC LR6 1 ; DEC LR7 1 ;;
    B tile ;;
last_tile:
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ;;
    SET LR5 LR8 ; DEC LR9 1 ;;
    INC LR5 1 ; BNE LR9 CR0 channel ;;
    HALT ;;
