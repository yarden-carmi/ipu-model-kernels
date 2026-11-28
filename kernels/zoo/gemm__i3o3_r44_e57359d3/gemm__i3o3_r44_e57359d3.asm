{% macro mac(first=false) %}MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR12 {{ cr.n }} ; DEC LR5 1 ; DEC LR8 1 ;;
feature:
    SET LR9 CR0 ; SET LR13 {{ cr.pitch }} ;;
row:
    SET LR4 LR8 ; SET LR2 LR9 ; SET LR7 {{ cr.k }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
tap:
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    {{ mac() }} ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    {{ mac() }} ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    {{ mac() }} ; DEC LR7 1 ; BEQ LR7 CR1 store ;;
    ADD LR2 LR2 {{ cr.pitch }} ; LD.MULT R0 LR2 {{ cr.in0 }} ; B tap ;;
store:
    BEQ LR13 CR1 last ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR9 1 ; DEC LR13 1 ; B row ;;
last:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; ADD LR8 LR8 {{ cr.wstride }} ; DEC LR12 1 ; BNE LR12 CR1 feature ;;
    HALT ;;
