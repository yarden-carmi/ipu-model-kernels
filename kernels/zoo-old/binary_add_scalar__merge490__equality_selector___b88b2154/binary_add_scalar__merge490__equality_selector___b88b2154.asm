{% set nb = s3_n // 128 %}
    INC LR1 128 ; INC LR12 {{ s2_tokens // 128 }} ; INC LR14 128 ;;
    INC LR15 {{ nb }} ;;
{% for start in range(0, s2_vocab, 255) %}
    INC LR13 {{ [255, s2_vocab-start] | min }} ;;
{% endfor %}
    LD.MULT R1 LR0 {{ cr.ones }} ;;
token_block:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
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
    INC LR6 {{ loop.index0 }} ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR6 CR1 ;;
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
    MULT.VE LR1 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
dot:
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
{% if s2_vocab > 490 %}
    SET LR10 CR0 ;;
    INC LR10 245 ;;
    INC LR10 245 ;;
    BNE LR9 LR10 normal_row ;;
    DEC LR7 {{ nb }} ;;
normal_row:
{% endif %}
    LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% if s2_vocab > 490 %}
    BNE LR9 LR10 normal_next ;;
    INC LR7 {{ nb }} ;;
normal_next:
{% endif %}
    INC LR6 1 ; INC LR7 {{ nb }} ; INC LR9 1 ;;
    BLT.S LR9 LR13 dot ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR15 channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
{% for start in range(0, s2_vocab, 255) %}
    INC LR3 {{ [255, s2_vocab-start] | min }} ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 block ;;
    SET LR2 CR0 ; SET LR8 CR0 ;;
second_row:
{% for c in range(s6_n // 128) %}
    SET LR7 CR0 ;;
    INC LR7 {{ c }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.v }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out1 }} LR8 ;;
    INC LR8 1 ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR14 second_row ;;
{% if s6_m == 256 %}
    SET LR2 CR0 ;;
second_row2:
{% for c in range(s6_n // 128) %}
    SET LR7 CR0 ;;
    INC LR7 {{ c }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.v }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out1 }} LR8 ;;
    INC LR8 1 ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR14 second_row2 ;;
{% endif %}
    HALT ;;
