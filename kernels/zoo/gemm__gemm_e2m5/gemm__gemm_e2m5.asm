    SET LR0 CR0 ;;
{% for stage in range(2) %}
    SET LR7 CR0 ;;
    SET LR10 CR0 ;;
    SET LR5 CR0 ;;
{% if stage == 0 %}
outer0:
    SET LR6 CR0 ;;
    SET LR11 CR0 ;;
block0:
    SET LR3 CR0 ;;
lane0:
    SET LR8 LR10 ;;
    SET LR4 LR11 ;;
{% else %}
outer1:
    SET LR6 CR0 ;;
    SET LR8 CR0 ;;
block1:
    SET LR3 CR0 ;;
lane1:
    SET LR4 LR10 ;;
{% endif %}
    SET LR9 CR0 ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR4 {{ cr['w' ~ stage] }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM.FIRST LR3 CR15.L ;;
    INC LR8 1 ; INC LR4 1 ; INC LR9 1 ;;
{% if (s0_k if stage == 0 else s1_k) > 128 %}
more{{ stage }}:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR4 {{ cr['w' ~ stage] }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR3 CR15.L ;;
    INC LR8 1 ; INC LR4 1 ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.K if stage == 0 else cr.K1 }} more{{ stage }} ;;
{% endif %}
{% if (s0_bias if stage == 0 else s1_bias) %}
    LD.MULT.CYCLIC {{ 'LR12' if stage == 0 else 'LR5' }} {{ cr['b' ~ stage] }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR3 CR15.L ;;
{% endif %}
{% if stage == 0 %}
    SET LR11 LR4 ;;
    INC LR12 1 ;;
{% endif %}
    INC LR3 1 ;;
    BLT.S LR3 LR14 lane{{ stage }} ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr['out' ~ stage] }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
{% if stage == 0 %}
    BLT.S LR12 {{ cr.s0_n }} block0 ;;
    SET LR12 CR0 ;;
    ADD LR10 LR10 {{ cr.K }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.s0_m }} outer0 ;;
{% else %}
    BLT.S LR6 LR15 block1 ;;
    ADD LR10 LR10 {{ cr.K1 }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.s1_n }} outer1 ;;
{% endif %}
{% endfor %}
    HALT ;;
