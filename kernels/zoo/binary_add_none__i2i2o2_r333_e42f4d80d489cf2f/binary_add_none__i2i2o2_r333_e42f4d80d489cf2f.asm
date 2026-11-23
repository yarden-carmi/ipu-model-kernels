{% macro add_store(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR3 1 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR1 {{ cr.in1 }} ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; SET LR4 {{ cr.width }} ;;
    DEC LR4 1 ;;
row:
    SET LR3 CR0 ; BEQ LR4 CR0 tail ;;
full:
    {{ add_store('CR15') }} ; BLT.S LR3 LR4 full ;;
tail:
    {{ add_store(cr.tail) }} ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
