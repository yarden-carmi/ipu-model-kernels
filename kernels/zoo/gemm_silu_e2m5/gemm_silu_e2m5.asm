    SET LR0 CR0 ;;
    SET LR10 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR10 ;;
    INC LR10 1 ;;
{% endfor %}
    SET LR11 CR0 ;;
    SET LR2 CR0 ;;
    SET LR5 CR0 ;;
    SET LR7 CR0 ;;
row_loop:
    SET LR6 CR0 ;;
nb_loop:
    SET LR4 LR6 ;;
    SET LR8 LR11 ;;
    LD.MULT.CYCLIC LR6 {{ cr.bias_vec }} LR0 ;;
    MULT.RC.VE LR0 {{ 'CR1' if bias else 'CR0' }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for block in range((k + 127) // 128) %}
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    INC LR8 1 ;;
    SET LR3 LR2 ;;
{% for i in range([128, k - block * 128] | min) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ADD LR4 LR4 {{ cr.nb }} ; INC LR3 1 ;;
{% endfor %}
{% endfor %}
    INC LR6 1 ;;
    BEQ LR6 {{ cr.nb }} tail_store ;;
    ACTIVATE.QUANTIZE generic CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ;;
    BLT.S LR6 {{ cr.nb }} nb_loop ;;
tail_store:
    ACTIVATE.QUANTIZE generic {{ cr.dsn }}.L {{ cr.qf }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ;;
    ADD LR1 LR2 {{ cr.sstep }} ;;
    BLT.S LR1 {{ cr.c128 }} no_carry ;;
    SUB LR1 LR1 {{ cr.c128 }} ;;
    INC LR11 1 ;;
no_carry:
    SET LR2 LR1 ;;
    ADD LR11 LR11 {{ cr.qstep }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} row_loop ;;
    HALT ;;
