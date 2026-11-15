{#- Embedding with floor-index indicator construction and exact row selection. -#}
{%- set ntb = tokens // 128 -%}
{%- set nd = dim // 128 -%}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR12 CR0 ;;
    INC LR1 128 ;;
tb_loop:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
    ADD LR3 LR2 CR0 ;;
{% for k in range(9) %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR1 {{ cr.six }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% for j in range(k) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.scr }} LR3 ;;
    INC LR3 {{ ntb }} ;;
{% endfor %}
    ADD LR4 LR2 CR0 ;;
{% for k in range(9) %}
    LD.MULT R0 LR4 {{ cr.scr }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
    MULT.VE LR1 {{ cr.neg1 }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.scr }} LR3 ;;
    INC LR3 {{ ntb }} ; INC LR4 {{ ntb }} ;;
{% endfor %}
    ADD LR4 LR2 CR0 ;;
    INC LR4 {{ 9 * ntb }} ;;
    ADD LR6 LR4 CR0 ;;
    INC LR6 {{ ntb }} ;;
{% for k in range(8) %}
    LD.MULT R1 LR4 {{ cr.scr }} ;;
    LD.MULT R0 LR6 {{ cr.scr }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.scr }} LR3 ;;
    INC LR3 {{ ntb }} ; INC LR4 {{ ntb }} ; INC LR6 {{ ntb }} ;;
{% endfor %}
    SET LR8 CR0 ; SET LR13 CR0 ;;
    INC LR13 128 ;;
j_loop:
{% for c in range(nd) %}
    SET LR7 CR0 ;;
    INC LR7 {{ c }} ;;
    ADD LR6 LR2 CR0 ;;
    INC LR6 {{ 18 * ntb }} ;;
{% for k in range(8) %}
    LD.MULT R0 LR6 {{ cr.scr }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.table }} LR0 ;;
    MULT.RC.VE LR0 LR8 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k == 0 else '' }} ;;
    INC LR6 {{ ntb }} ; INC LR7 {{ nd }} ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ;;
{% endfor %}
    INC LR8 1 ;;
    BLT.S LR8 LR13 j_loop ;;
    INC LR2 1 ;;
    SET LR14 CR0 ;;
    INC LR14 {{ ntb }} ;;
    BLT.S LR2 LR14 tb_loop ;;
    HALT ;;
