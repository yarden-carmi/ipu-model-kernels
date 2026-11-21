{% set NC = (n + 127) // 128 %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR5 CR0 ; SET LR10 CR0 ;;
batch:
    SET LR6 CR0 ;;
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    SET LR3 LR10 ;;
    SUB LR3 LR3 CR1 ;;
{% for t in range(NC) %}
    SET LR7 CR0 ; SET LR8 {{ cr.lastwidth if t == NC - 1 else cr.width }} ;;
    SUB LR7 LR7 CR1 ;;
inner_{{ t }}:
    LD.MULT.CYCLIC LR3 {{ cr.in1 }} LR0 ; INC LR3 1 ; INC LR7 1 ; DEC LR8 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.kds }}.L {{ cr.qf }}.L ; AGG.SUM.FIRST LR7 {{ cr.kds }}.L ; BNE LR8 CR0 inner_{{ t }} ;;
    ACTIVATE.QUANTIZE identity {{ cr.last if t == NC - 1 else cr.full }}.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
{% endfor %}
    INC LR1 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.m }} row ;;
    ADD LR10 LR10 {{ cr.n }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.b }} batch ;;
    HALT ;;
