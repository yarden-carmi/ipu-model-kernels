{% set nbi = cin // 128 %}
{% set nbo = cout // 128 %}
    SET LR0 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
{% if i < 4 %}
    INC LR0 1 ;;
{% endif %}
{% endfor %}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR4 {{ cr.start }} ;;
    SET LR6 CR0 ;;
copy:
{% for ib in range(nbi) %}
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.dsfull }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf }}.L {{ cr.pad }} LR4 ;;
    INC LR2 1 ; INC LR4 1 ;;
{% endfor %}
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.w }} copy ;;
    SET LR3 CR0 ;;
    SET LR11 CR0 ;;
    SET LR12 CR0 ;;
oy:
    SET LR2 LR3 ;;
    SET LR10 CR0 ;;
ox:
    SET LR15 CR0 ;;
ob:
    LD.MULT.CYCLIC LR15 {{ cr.bias_vec }} LR0 ;;
    SET LR8 LR15 ;;
    MULT.RC.VE LR0 {{ 'CR1' if bias else 'CR0' }} 0 LR0 {{ cr.dsfull }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% if stride == 2 %}
    BEQ CR0 CR0 store ;;
{% else %}
    BNE LR11 CR1 store ;;
{% endif %}
    SET LR5 LR2 ;;
{% for tap in range(kw) %}
{% for ib in range(nbi) %}
    LD.MULT R0 LR5 {{ cr.pad }} ;;
    SET LR9 CR0 ;;
    SET LR7 CR0 ;;
    INC LR7 128 ;;
ic_{{ tap }}_{{ ib }}:
{% for u in range(8) %}
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.dsfull }}.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR8 {{ nbo }} ; INC LR9 1 ;;
{% endfor %}
    BLT.S LR9 LR7 ic_{{ tap }}_{{ ib }} ;;
    INC LR5 1 ;;
{% endfor %}
{% endfor %}
store:
    ACTIVATE.QUANTIZE generic {{ cr.dsfull }}.L {{ cr.qf }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ; INC LR15 1 ;;
    BLT.S LR15 {{ cr.nbo }} ob ;;
    INC LR2 {{ stride * nbi }} ; INC LR10 1 ;;
    BLT.S LR10 {{ cr.wo }} ox ;;
{% for s in range(stride) %}
    ADD LR3 LR3 {{ cr.wpr }} ;;
{% endfor %}
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.ho }} oy ;;
    HALT ;;
