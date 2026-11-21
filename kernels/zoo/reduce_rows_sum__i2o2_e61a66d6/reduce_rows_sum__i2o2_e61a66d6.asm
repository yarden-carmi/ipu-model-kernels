{% macro body(ds, lbl) %}
    SET LR1 LR5 ;;
    LD.MULT R1 LR1 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ADD LR1 LR1 {{ cr.rb }} ;;
    SET LR4 {{ cr.in0_d3 }} ;;
    DEC LR4 1 ;;
{{ lbl }}:
    LD.MULT R1 LR1 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    ADD LR1 LR1 {{ cr.rb }} ;;
    DEC LR4 1 ;;
    BNE LR4 CR0 {{ lbl }} ;;
    ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
    INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.one }} LR0 ;;
    SET LR3 CR0 ;;
    SET LR5 CR0 ;;
gloop:
    SET LR9 CR0 ;;
    BLT.S LR9 {{ cr.rbm1 }} full ;;
    SET LR10 CR1 ;;
    BNE LR10 CR0 last ;;
full:
{{ body("CR15", "in1") }}
    INC LR9 1 ;;
    BLT.S LR9 {{ cr.rbm1 }} full ;;
last:
{{ body("CR14", "in2") }}
    ADD LR5 LR5 {{ cr.skip }} ;;
    BLT.S LR3 {{ cr.total }} gloop ;;
    HALT ;;
