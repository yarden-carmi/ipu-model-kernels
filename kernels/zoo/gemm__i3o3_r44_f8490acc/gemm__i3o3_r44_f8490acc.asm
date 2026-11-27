    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    DEC LR5 1 ;;
    SET LR9 {{ cr.n }} ;;
    SET LR14 CR1 ;;
    INC LR14 1 ;;
    SET LR15 {{ cr.tiles }} ;;
    ADD LR15 LR15 {{ cr.tiles }} ;;
channel:
    SET LR10 {{ cr.in0_d0 }} ; SET LR11 CR0 ;;
batch:
    SET LR12 {{ cr.tiles }} ; SET LR13 LR11 ;;
tile:
    SUB LR4 LR13 LR11 ; SET LR2 LR13 ; SET LR6 {{ cr.k }} ;;
    ADD LR4 LR4 LR4 ;;
    ADD LR4 LR8 LR4 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    ADD LR4 LR8 LR15 ;;
dot:
    LD.MULT R0 LR4 {{ cr.w }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR4 {{ cr.w }} ; ADD LR2 LR2 {{ cr.tiles }} ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 ; DEC LR6 1 ; BNE LR6 CR1 dot ;;
{% if (in0_d2 * in0_d3) % 256 != 0 %}
{% if (in0_d2 * in0_d3) % 256 <= 128 %}
    BEQ LR12 CR1 zero_store ;;
{% if (in0_d2 * in0_d3) % 128 != 0 %}
    BEQ LR12 LR14 tail_store ;;
{% endif %}
{% else %}
    BEQ LR12 CR1 tail_store ;;
{% endif %}
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
    B stored ;;
{% if (in0_d2 * in0_d3) % 256 != 0 and (in0_d2 * in0_d3) % 128 != 0 %}
tail_store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
    B stored ;;
{% endif %}
{% if (in0_d2 * in0_d3) % 256 != 0 and (in0_d2 * in0_d3) % 256 <= 128 %}
zero_store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.empty }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endif %}
stored:
    INC LR13 1 ; DEC LR12 1 ;;
    BNE LR12 CR0 tile ;;
    ADD LR11 LR11 {{ cr.batchrows }} ; DEC LR10 1 ;;
    BNE LR10 CR0 batch ;;
    ADD LR8 LR8 {{ cr.twok }} ; DEC LR9 1 ;;
    ADD LR8 LR8 LR15 ;;
    BNE LR9 CR0 channel ;;
    HALT ;;
