    INC LR1 128 ; INC LR12 {{ s0_tokens // 128 }} ; INC LR14 128 ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
token:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% for branch in [0,1] %}
{% for k in range(8 if branch == 0 else 9) %}
{% for side in [0,1] %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if side == 0 else 'ADD' }}.FIRST ;;
{% if branch == 1 %}
    LD.MULT.CYCLIC LR0 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if side == 0 else 'ADD' }} ;;
{% endif %}
{% set bound = k if branch == 1 else ((k if k > 0 else -1) if side == 0 else k+1) %}
{% for j in range(bound|abs) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if (side == 0 and bound > 0) or (side == 1 and bound < 0) else 'SUB' }} ;;
{% endfor %}
{% if branch == 0 and (side == 1 or k == 0) %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    SET LR6 CR{{ side }} ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR6 CR1 ;;
    LD.MULT.CYCLIC LR6 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
    INC LR3 1 ;;
{% endfor %}
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 token ;;
    SET LR2 CR0 ;;
block:
    SET LR4 CR0 ;;
lane:
{% for branch in [0,1] %}
    SET LR5 CR0 ;;
    INC LR13 {{ (s1_n if branch == 0 else s5_n) // 128 }} ;;
channel{{ branch }}:
    SET LR6 LR2 ; SET LR7 LR5 ;;
{% if branch == 1 %}
    INC LR6 8 ;;
{% endif %}
{% for k in range(8 if branch == 0 else 9) %}
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w0 if branch == 0 else cr.w5 }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k == 0 else '' }} ;;
    INC LR6 1 ; INC LR7 {{ (s1_n if branch == 0 else s5_n) // 128 }} ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 if branch == 0 else cr.out1 }} LR{{ 8 if branch == 0 else 9 }} ;;
    INC LR{{ 8 if branch == 0 else 9 }} 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 channel{{ branch }} ;;
    SET LR13 CR0 ;;
{% endfor %}
{% for c in range(s8_n // 128) %}
    SET LR6 CR0 ;;
    INC LR6 {{ c }} ;;
    LD.MULT R0 LR6 {{ cr.w8 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out2 }} LR10 ;;
    INC LR10 1 ;;
{% endfor %}
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
    INC LR11 1 ; INC LR2 17 ;;
    BLT.S LR11 LR12 block ;;
    HALT ;;
