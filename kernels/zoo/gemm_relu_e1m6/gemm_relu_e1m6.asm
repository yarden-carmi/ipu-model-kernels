    INC LR14 128 ;;
row:
{% for b in range((n + 127) // 128) %}
    SET LR1 LR10 ;;
    SET LR2 CR0 ;;
    INC LR2 {{ b }} ;;
    SET LR3 CR0 ;;
    SET LR4 CR0 ;;
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
{% if bias %}
    SET LR5 CR0 ;;
    INC LR5 {{ b }} ;;
    LD.MULT R1 LR5 {{ cr.bias_vec }} ;;
    MULT.VE LR14 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% else %}
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% endif %}
k_loop_{{ b }}:
    LD.MULT.CYCLIC LR2 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR2 {{ (n + 127) // 128 }} ;;
    INC LR4 1 ;;
    INC LR3 1 ;;
    BLT.S LR3 LR14 ready_{{ b }} ;;
    SET LR3 CR0 ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
ready_{{ b }}:
    BLT.S LR4 {{ cr.k }} k_loop_{{ b }} ;;
    ACTIVATE.QUANTIZE relu {{ cr.tail_ds if b == (n + 127) // 128 - 1 else 'CR15' }}.L {{ cr.qf }}.L {{ cr.out0 }} LR11 ;;
    INC LR11 1 ;;
{% endfor %}
    INC LR10 {{ (k + 127) // 128 }} ;;
    INC LR12 1 ;;
    BLT.S LR12 {{ cr.m }} row ;;
    HALT ;;
