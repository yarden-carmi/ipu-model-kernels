{% set nb = s2_n // 128 %}
{% set nt = s1_tokens // 128 %}
    INC LR1 128 ; INC LR12 {{ nt }} ;;
{% for start in range(0, s1_vocab, 255) %}
    INC LR13 {{ [255, s1_vocab-start] | min }} ;;
{% endfor %}
    INC LR14 128 ; INC LR15 {{ nb }} ;;
token_block:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
    SET LR4 CR0 ;;
compare:
{% for sign in [1,-1] %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }}.FIRST ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }} ;;
    SET LR5 CR0 ;;
    BEQ LR4 LR0 boundary_done_{{ loop.index }} ;;
boundary_{{ loop.index }}:
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if sign == 1 else 'ADD' }} ;;
    INC LR5 1 ;;
    BLT.S LR5 LR4 boundary_{{ loop.index }} ;;
boundary_done_{{ loop.index }}:
    SET LR6 CR0 ;;
    INC LR6 {{ 1 if sign == 1 else 2 }} ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR6 CR1 ;;
    LD.MULT.CYCLIC LR6 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR6 1 ;;
    LD.MULT.CYCLIC LR6 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
    INC LR3 1 ; INC LR4 1 ;;
    BLT.S LR4 LR13 compare ;;
    INC LR2 1 ;;
    BLT.S LR2 LR12 token_block ;;
    SET LR2 CR0 ; SET LR3 CR0 ;;
block:
    SET LR4 CR0 ;;
lane:
    SET LR5 CR0 ;;
channel:
    SET LR6 LR3 ; SET LR7 LR5 ; SET LR9 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
dot:
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR6 1 ; INC LR7 {{ nb }} ; INC LR9 1 ;;
    BLT.S LR9 LR13 dot ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
{% if s3_sel // 128 < nb %}
    SET LR10 CR0 ;;
    INC LR10 {{ s3_sel // 128 }} ;;
    BNE LR5 LR10 not_scan ;;
    SET LR10 CR0 ;;
    INC LR10 3 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR10 ;;
not_scan:
{% endif %}
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR15 channel ;;
    SET LR10 CR0 ;;
    INC LR10 3 ;;
    LD.MULT R0 LR10 {{ cr.work }} ;;
    LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
    SET LR10 CR0 ;;
    INC LR10 {{ s3_sel % 128 }} ;;
    MULT.RC.VE LR0 LR10 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR10 CR0 ;;
    INC LR10 4 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR10 ;;
    LD.MULT R0 LR10 {{ cr.work }} ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
{% for sign in [1,-1] %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }}.FIRST ;;
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR10 CR0 ;;
    INC LR10 {{ 4 if sign == 1 else 5 }} ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR10 ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR10 CR0 ;;
    INC LR10 4 ;;
    LD.MULT.CYCLIC LR10 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR10 1 ;;
    LD.MULT.CYCLIC LR10 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.work }} LR10 ;;
    LD.MULT R0 LR10 {{ cr.work }} ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR10 ;;
    LD.MULT R0 LR10 {{ cr.work }} ;;
{% for c in range(s5_n // 128) %}
    SET LR10 CR0 ;;
    INC LR10 {{ c }} ;;
    LD.MULT.CYCLIC LR10 {{ cr.v }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out1 }} LR11 ;;
    INC LR11 1 ;;
{% endfor %}
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
{% for start in range(0, s1_vocab, 255) %}
    INC LR3 {{ [255, s1_vocab-start] | min }} ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 block ;;
    HALT ;;
