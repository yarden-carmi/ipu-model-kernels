{% set pack = 128 // in0_d3 %}
{% macro loadw() %}LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1{% endmacro %}
{% macro tap(i) %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadw() }} ; SET LR12 LR3 ;;
    MULT.RC.VE LR0 LR12 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadw() }} ; DEC LR7 1 {% if i + 1 < pack %}; INC LR3 {{ in0_d3 }}{% endif %} ; BEQ LR7 CR1 finished ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    DEC LR5 1 ; SET LR10 {{ cr.rows }} ;;
row:
    SET LR11 CR0 ;;
pixel:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
    {{ loadw() }} ;;
tile:
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ loadw() }} ; SET LR2 LR8 ; SET LR7 {{ cr.k }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadw() }} ;;
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR3 LR11 ;;
    INC LR2 1 ;;
{% for i in range(pack) %}{{ tap(i) }}{% endfor %}
    B chunk ;;
finished:
    DEC LR6 1 ; BEQ LR6 CR1 last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; B tile ;;
last_tile:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR11 1 ; BLT.S LR11 {{ cr.width }} pixel ;;
    ADD LR8 LR8 {{ cr.chunks }} ; DEC LR10 1 ; BNE LR10 CR1 row ;;
    HALT ;;
