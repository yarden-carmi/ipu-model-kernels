{% macro loadcoef() %}LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    SET LR9 {{ cr.n }} ; DEC LR3 1 ;;
channel:
    SET LR6 CR0 ; SET LR7 {{ cr.tiles }} ;;
tile:
    SET LR8 LR5 ; SUB LR2 LR6 {{ cr.tiles }} ; SET LR4 {{ cr.k }} ;;
    DEC LR8 1 ;;
    {{ loadcoef() }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ loadcoef() }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef() }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.tiles }} ;;
    {{ loadcoef() }} ;;
{% if k <= 32 %}
{% for i in range(k) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef() }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef() }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if not loop.last %}; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.tiles }}{% endif %} ;;
{% if not loop.last %}
    {{ loadcoef() }} ;;
{% endif %}
{% endfor %}
{% else %}
reduce:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef() }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef() }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR4 1 ;;
    BEQ LR4 CR0 finish ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.tiles }} ;;
    {{ loadcoef() }} ; B reduce ;;
finish:
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.store_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; INC LR6 1 ; DEC LR7 1 ;;
    BNE LR7 CR0 tile ;;
    SET LR5 LR8 ; DEC LR9 1 ;;
    INC LR5 1 ; BNE LR9 CR0 channel ;;
    HALT ;;
