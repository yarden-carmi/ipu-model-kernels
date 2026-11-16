    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    SET LR4 {{ cr.reg_offset }} ;;
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    SET LR3 CR0 ;;
element:
    MULT.EE LR3 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R1 LR2 {{ cr.in1 }} ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR12 {{ cr.indices_lo }} ;;
    SET LR13 {{ cr.indices_hi }} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.RESHAPE LRD10 LRD12 1 ;;
{% for i in range(15) %}
    ADDBI LRD12 8 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.RESHAPE LRD10 LRD12 0 ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.width }} element ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
