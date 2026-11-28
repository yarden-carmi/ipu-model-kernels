{% macro pixel_loop(digit) %}
    ADD LR6 LR11 LR1 ; SET LR9 {{ cr.in0_d2 }} ; SET LR3 LR2 ;;
    DEC LR3 1 ; DEC LR9 1 ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
    BEQ LR9 CR0 pixel_end_{{ digit }} ;;
pixel_{{ digit }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR3 1 ; ADD LR6 LR6 {{ cr.step }} ; DEC LR9 1 ; LD.MULT R0 LR6 {{ cr.in0 }} ; BNE LR9 CR1 pixel_{{ digit }} ;;
pixel_end_{{ digit }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR3 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR15 CR0 ;;
    DEC LR5 1 ;;
batch:
    SET LR10 CR0 ; SET LR7 {{ cr.n }} ;;
feature:
    SET LR11 LR15 ; SET LR12 {{ cr.in0_d3 }} ;;
row:
    SET LR4 LR10 ; LD.MULT.CYCLIC LR10 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR1 CR0 ; SET LR8 {{ cr.chunks }} ;;
chunk:
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; SET LR2 CR0 ;;
    {{ pixel_loop('a') }}
    {% if in0_d3 > 1 %}
    BEQ LR12 CR1 skip_a ;;
    ADD LR11 LR11 {{ cr.chunks }} ; SET LR2 {{ cr.in0_d2 }} ;;
    {{ pixel_loop('b') }}
    SUB LR11 LR11 {{ cr.chunks }} ;;
skip_a:
    {% endif %}
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; SET LR2 CR0 ;;
    {{ pixel_loop('c') }}
    {% if in0_d3 > 1 %}
    BEQ LR12 CR1 skip_b ;;
    ADD LR11 LR11 {{ cr.chunks }} ; SET LR2 {{ cr.in0_d2 }} ;;
    {{ pixel_loop('d') }}
    SUB LR11 LR11 {{ cr.chunks }} ;;
skip_b:
    {% endif %}
    INC LR1 1 ; DEC LR8 1 ; BNE LR8 CR1 chunk ;;
    BEQ LR12 CR1 final_row ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
    ADD LR11 LR11 {{ cr.chunks }} ; DEC LR12 2 ;;
    ADD LR11 LR11 {{ cr.chunks }} ; BNE LR12 CR0 row ;;
    B next_feature ;;
final_row:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
next_feature:
    ADD LR10 LR10 LR13 ; DEC LR7 1 ; BNE LR7 CR1 feature ;;
    ADD LR15 LR15 {{ cr.batch_stride }} ; DEC LR14 1 ; BNE LR14 CR1 batch ;;
    HALT ;;
