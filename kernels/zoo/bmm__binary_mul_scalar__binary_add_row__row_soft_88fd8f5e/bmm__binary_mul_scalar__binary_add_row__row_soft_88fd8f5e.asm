{% set kd = cr.dot_and_row ~ '.L' %}
{% set d = cr.dot_and_row ~ '.H' %}
{% set s = cr.single_and_work ~ '.L' %}
{% set w = cr.single_and_work ~ '.H' %}
{% set q = cr.qf_out0 ~ '.L' %}
{% set t = cr.tmp %}

{% macro next_head(label) %}
    ADD LR2 LR2 {{ cr.s0_k }} ; DEC LR3 1 ; BEQ LR3 CR1 {{ label }}_done ;;
    BLT.S LR2 LR13 {{ label }} ;;
    DEC LR2 128 ; INC LR1 1 ; B {{ label }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ;;
convert_loop:
    LD.MULT R0 LR4 {{ cr.operand }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ d }} {{ cr.qf_operand }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ d }} {{ q }} {{ cr.converted }} LR4 ;;
    INC LR4 1 ; BNE LR4 LR5 convert_loop ;;
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR6 CR0 ; SET LR9 LR3 ; SET LR13 CR0 ;;
    INC LR13 128 ;;
    ADD LR14 LR13 LR13 ;;
pack_head:
    SET LR4 LR1 ; SET LR5 {{ cr.s0_n }} ;;
pack_row:
    LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR2 CR1 0 LR0 {{ kd }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ kd }} {{ cr.qf_in0 }}.L {{ cr.packed }} LR6 ;;
    INC LR6 1 ; ADD LR4 LR4 LR7 ; DEC LR5 1 ; BNE LR5 CR1 pack_row ;;
    {{ next_head('pack_head') }}
pack_head_done:
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 LR9 ;;
    SET LR6 CR0 ; SET LR5 LR8 ; SET LR9 CR0 ;;
    SET LR4 LR14 ;;
    INC LR4 128 ;;
    LD.MULT.CYCLIC LR0 {{ cr.converted }} LR13 ;;
    SET LR12 CR1 ; LD.MULT.CYCLIC LR12 {{ cr.converted }} LR14 ;;

compute_head:
    SET LR7 LR1 ; SET LR8 LR5 ; SET LR12 CR1 ;;
    INC LR12 2 ;;
compute_row:
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ; SET LR10 LR6 ; SET LR11 CR0 ;;
dot_loop:
    LD.MULT R0 LR10 {{ cr.packed }} ;;
    MULT.RC.VV LR2 R0 0 LR0 {{ kd }} {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ kd }} ;;
    INC LR10 1 ; INC LR11 1 ;;
    BNE LR11 {{ cr.s0_n }} dot_loop ;;
    ACTIVATE.QUANTIZE identity {{ d }} {{ q }} {{ t }} LR0 ;;

    LD.MULT R0 LR0 {{ t }} ; SET LR10 CR1 ;;
    INC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.converted }} LR4 ;;
    MULT.RC.VV LR4 R0 0 LR0 {{ d }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ d }} {{ q }} {{ t }} LR0 ;;
    LD.MULT R0 LR0 {{ t }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ d }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR12 {{ cr.operand }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ d }} {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ d }} {{ q }} {{ t }} LR0 ;;

    LD.MULT R0 LR0 {{ t }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ d }} {{ q }} ; AGG.MAX.FIRST LR0 {{ d }} ; ACTIVATE.QUANTIZE identity {{ s }} {{ q }} {{ t }} LR0 ;;
    LD.MULT R1 LR0 {{ t }} ;;
{% for coeff in ['LR13', 'LR14'] %}
    MULT.RC.VV {{ coeff }} R0 0 LR0 {{ d }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE {{ coeff }} LR13 0 LR0 {{ d }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ d }} {{ w }} {{ t }} LR0{% endif %} ;;
{% endfor %}
    LD.MULT.CYCLIC LR0 {{ t }} LR4 ;;
    MULT.RC.VE LR4 CR1 0 LR0 {{ d }} {{ w }} ; AGG.SUM.FIRST LR0 {{ d }} ; ACTIVATE.QUANTIZE reciprocal {{ s }} {{ w }} {{ t }} LR0 ;;
    LD.MULT R1 LR0 {{ t }} ;;
    MULT.RC.VE LR4 LR13 0 LR0 {{ d }} {{ w }} ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ d }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ; INC LR12 1 ; ADD LR7 LR7 LR15 ;;
    DEC LR8 1 ; BNE LR8 CR1 compute_row ;;
    ADD LR6 LR6 {{ cr.s0_n }} ;;
    {{ next_head('compute_head') }}
compute_head_done:
    HALT ;;
