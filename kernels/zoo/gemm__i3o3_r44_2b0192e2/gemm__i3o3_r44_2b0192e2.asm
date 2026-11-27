{% macro tap(i) %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR6 LR6 {{ cr.tiles }} ;;
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR8 1 ; INC LR9 1 ;;
{% endmacro %}
{% macro group(count) %}
    LD.MULT R0 LR3 {{ cr.coeff }} ; SET LR8 CR0 ; SET LR9 CR0 ;;
    LD.MULT R1 LR3 {{ cr.coeff }} ; INC LR3 1 ; INC LR9 127 ;;
    INC LR3 1 ;;
{% for i in range(count) %}{{ tap(i) }}{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR7 CR0 ;;
    SET LR15 {{ cr.n }} ;;
feature:
    SET LR1 CR0 ; SET LR4 {{ cr.tiles }} ;;
tile:
    SET LR6 LR1 ; SET LR3 LR7 ; LD.MULT R0 LR7 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR3 1 ; LD.MULT R0 LR3 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 ;;
{% if k // 16 %}
    SET LR10 CR0 ;;
    INC LR10 {{ k // 16 }} ;;
group:
    {{ group(16) }}
    DEC LR10 1 ;;
    BNE LR10 CR0 group ;;
{% endif %}
{% if k % 16 %}{{ group(k % 16) }}{% endif %}
    BEQ LR4 CR1 last ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR1 1 ; DEC LR4 1 ;;
    INC LR2 1 ;;
    B tile ;;
last:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; SET LR7 LR3 ; DEC LR15 1 ;;
    INC LR2 1 ;;
    BNE LR15 CR0 feature ;;
    HALT ;;
