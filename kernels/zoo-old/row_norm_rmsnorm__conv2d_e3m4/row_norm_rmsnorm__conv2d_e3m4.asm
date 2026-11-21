    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR3 128 ;;
row:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM.FIRST LR0 CR15.L ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR4 CR0 ;;
    INC LR4 6 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR4 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.recip }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR0 {{ cr.reciplo }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.recip }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    LD.MULT R0 LR0 {{ cr.epsilon }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE rsqrt CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR4 CR0 ;;
    INC LR4 4 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR4 ;;
    LD.MULT R0 LR4 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR4 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR4 ;;
    DEC LR4 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.gamma }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR4 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 LR13 row ;;
{% set nb = (s1_cin+127)//128 %}
{% set ow = (s1_w-1)//s1_stride+1 %}
    SET LR9 CR0 ; SET LR10 CR0 ; SET LR12 CR0 ;;
    SET LR14 CR0 ;;
{% for n in range(0,s1_cout,255) %}
    INC LR14 {{ [255,s1_cout-n]|min }} ;;
{% endfor %}
co:
    SET LR7 CR0 ; SET LR11 CR0 ;;
oy:
    SET LR6 CR0 ; SET LR3 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR14.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
ox:
    ADD LR5 LR7 LR6 ; ADD LR8 LR9 CR0 ;;
{% for ib in range(nb) %}
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
    LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR14.H {{ cr.qf }}.L ; AGG.SUM LR3 {{ 'CR13' if ib == nb-1 else 'CR14' }}.{{ 'L' if ib == nb-1 else 'H' }} ; INC LR8 1 ; INC LR5 1 ;;
{% endfor %}
    INC LR6 {{ s1_stride*nb }} ; INC LR3 1 ;;
    {% for ox in [] %}{% endfor %}
    SET LR4 CR0 ;;
    INC LR4 {{ ow }} ;;
    BLT.S LR3 LR4 ox ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsout }}.L {{ cr.qf }}.L {{ cr.out1 }} LR12 ;;
    INC LR12 1 ; INC LR11 1 ;;
{% for n in range(0,s1_stride*s1_w*nb,255) %}
    INC LR7 {{ [255,s1_stride*s1_w*nb-n]|min }} ;;
{% endfor %}
    BLT.S LR11 LR15 oy ;;
    INC LR9 {{ nb }} ; INC LR10 1 ;;
    BLT.S LR10 LR14 co ;;
    HALT ;;
