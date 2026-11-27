{% macro mac() %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; INC LR2 1 ; INC LR3 1 ; BLT.S LR3 {{ cr.last }} lane ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 {{ cr.minusone }} ; SET LR6 {{ cr.minusone }} ;;
    SET LR10 {{ cr.n }} ;;
channel:
    SET LR8 {{ cr.minusone }} ; SET LR9 {{ cr.in0_d2 }} ;;
row:
    SET LR4 LR6 ; SET LR2 LR8 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ; SET LR3 {{ cr.minusone }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; INC LR2 1 ;;
{% if k > 1 %}
lane:
    {{ mac() }}
{% endif %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; ADD LR8 LR8 {{ cr.k }} ; DEC LR9 1 ;;
    BNE LR9 CR0 row ;;
    SET LR6 LR4 ; DEC LR10 1 ; BNE LR10 CR1 channel ;;
    HALT ;;
