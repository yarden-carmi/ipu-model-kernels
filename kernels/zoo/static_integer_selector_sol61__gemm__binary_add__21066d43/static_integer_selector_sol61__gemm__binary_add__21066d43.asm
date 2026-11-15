{% for branch in range(2) %}
{% set ke = [s0_vocab,8]|min if branch == 0 else [s3_vocab,9]|min %}
{% set nt = s0_tokens // 128 if branch == 0 else s3_tokens // 128 %}
{% set nb = s1_n // 128 if branch == 0 else s4_n // 128 %}
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR11 CR0 ;;
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR14 CR0 ;;
    INC LR1 128 ; INC LR11 1 ; INC LR12 {{nt}} ;;
    INC LR13 {{nb}} ; INC LR14 128 ;;
    LD.MULT R1 LR0 {{cr.ones}} ;;
tokens_{{branch}}:
    LD.MULT R0 LR2 {{cr.in0 if branch == 0 else cr.in1}} ;;
{% for k in range(ke) %}
{% for sign in [1,-1] %}
    MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.H {{cr.qf}}.L ; ACC.{{'ADD' if sign == 1 else 'SUB'}}.FIRST ;;
{% if branch == 0 %}
{% for j in range(k+1 if sign == 1 else k) %}
    MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.H {{cr.qf}}.L ; ACC.{{'SUB' if sign == 1 else 'ADD'}} ;;
{% endfor %}
{% if sign == 1 %}
    MULT.VE LR1 {{cr.edge}} 0 LR0 CR15.H {{cr.qf}}.L ; ACC.ADD ;;
{% endif %}
{% else %}
    MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.H {{cr.qf}}.L ; ACC.{{'ADD' if sign == 1 else 'SUB'}} ;;
{% for j in range(k) %}
    MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.H {{cr.qf}}.L ; ACC.{{'SUB' if sign == 1 else 'ADD'}} ;;
{% endfor %}
{% endif %}
    ACTIVATE.QUANTIZE relu6 CR15.H {{cr.qf}}.L {{cr.work}} {{'LR0' if sign == 1 else 'LR11'}} ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR0 {{cr.work}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.H {{cr.qf}}.L ; ACC.SUB ;;
    LD.MULT.CYCLIC LR11 {{cr.work}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.H {{cr.qf}}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.H {{cr.qf}}.L {{cr.selectors}} LR3 ;;
    INC LR3 1 ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 tokens_{{branch}} ;;
    SET LR2 CR0 ;;
{% if branch == 1 %}
    SET LR11 CR0 ;;
{% endif %}
block_{{branch}}:
    SET LR4 CR0 ;;
lane_{{branch}}:
    SET LR5 CR0 ;;
channel_{{branch}}:
    SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(ke) %}
    LD.MULT R0 LR6 {{cr.selectors}} ;;
    LD.MULT.CYCLIC LR7 {{cr.w if branch == 0 else cr.u}} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.H {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k == 0 else ''}} ;;
    INC LR6 1 ; INC LR7 {{nb}} ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.H {{cr.qf}}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.H {{cr.qf}}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.H {{cr.qf}}.L {{cr.out0 if branch == 0 else cr.out1}} LR8 ;;
{% if branch == 1 %}
    SET LR10 CR0 ;;
    INC LR10 {{s5_sel // 128}} ;;
    BNE LR5 LR10 skip_scan ;;
    SET LR10 CR0 ;;
    INC LR10 3 ;;
    ACTIVATE.QUANTIZE identity CR15.H {{cr.qf}}.L {{cr.work}} LR10 ;;
skip_scan:
{% endif %}
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 channel_{{branch}} ;;
{% if branch == 1 %}
    SET LR10 CR0 ;;
    INC LR10 3 ;;
    LD.MULT R0 LR10 {{cr.work}} ;;
    LD.MULT.CYCLIC LR0 {{cr.ones}} LR0 ;;
    SET LR10 CR0 ;;
    INC LR10 {{s5_sel % 128}} ;;
    MULT.RC.VE LR0 LR10 0 LR0 CR15.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    SET LR10 CR0 ;;
    INC LR10 4 ;;
    ACTIVATE.QUANTIZE identity CR15.H {{cr.qf}}.L {{cr.work}} LR10 ;;
    LD.MULT R0 LR10 {{cr.work}} ;;
{% for sign in [1,-1] %}
    MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.H {{cr.qf}}.L ; ACC.{{'ADD' if sign == 1 else 'SUB'}}.FIRST ;;
    MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.H {{cr.qf}}.L ; ACC.SUB ;;
    MULT.VE LR1 {{cr.edge}} 0 LR0 CR15.H {{cr.qf}}.L ; ACC.ADD ;;
    SET LR10 CR0 ;;
    INC LR10 {{4 if sign == 1 else 5}} ;;
    ACTIVATE.QUANTIZE relu6 CR15.H {{cr.qf}}.L {{cr.work}} LR10 ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for j in [4,5] %}
    SET LR10 CR0 ;;
    INC LR10 {{j}} ;;
    LD.MULT.CYCLIC LR10 {{cr.work}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.H {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu CR15.H {{cr.qf}}.L {{cr.work}} LR10 ;;
    LD.MULT R0 LR10 {{cr.work}} ;;
    MULT.VE LR1 CR1 0 LR0 CR15.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 CR1 0 LR0 CR15.H {{cr.qf}}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.H {{cr.qf}}.L {{cr.work}} LR10 ;;
    LD.MULT R0 LR10 {{cr.work}} ;;
{% for c in range(s7_n // 128) %}
    SET LR10 CR0 ;;
    INC LR10 {{c}} ;;
    LD.MULT.CYCLIC LR10 {{cr.v}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.H {{cr.qf}}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.H {{cr.qf}}.L {{cr.out2}} LR11 ;;
    INC LR11 1 ;;
{% endfor %}
{% endif %}
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane_{{branch}} ;;
    INC LR9 1 ; INC LR2 {{ke}} ;;
    BLT.S LR9 LR12 block_{{branch}} ;;
{% endfor %}
    HALT ;;
