    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR7 CR0 ;;
    SET LR10 CR0 ;;
n_loop:
    SET LR5 CR0 ;;
    SET LR6 CR0 ;;
mb_loop:
    MULT.EE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR2 CR0 ;;
lane_loop:
    SET LR3 LR6 ;;
    SET LR4 LR10 ;;
    SET LR8 {{ cr.K }} ;;
k_loop:
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
{% macro piece() %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 CR15.L ; INC LR4 1 ;;
{% endmacro %}
{% for i in range(3) %}
{{ piece() }}
{% endfor %}
    INC LR3 1 ; DEC LR8 1 ;;
    BNE LR8 CR0 k_loop ;;
{% if bias %}
    SET LR9 LR1 ;;
{% macro bias_piece() %}
    LD.MULT R0 LR9 {{ cr.b }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 CR15.L ; ADD LR9 LR9 {{ cr.n }} ;;
{% endmacro %}
{% for i in range(3) %}
{{ bias_piece() }}
{% endfor %}
{% endif %}
    ADD LR6 LR6 {{ cr.K }} ; INC LR5 1 ; INC LR2 1 ;;
    BGE.S LR5 {{ cr.m }} store ;;
    BLT.S LR2 {{ cr.c128 }} lane_loop ;;
store:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ;;
    BLT.S LR5 {{ cr.m }} mb_loop ;;
    SET LR10 LR4 ; INC LR1 1 ;;
    BLT.S LR1 {{ cr.n }} n_loop ;;
    HALT ;;
