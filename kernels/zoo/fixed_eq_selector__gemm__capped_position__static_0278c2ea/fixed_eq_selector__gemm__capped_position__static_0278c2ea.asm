    INC LR1 128 ; INC LR11 1 ; INC LR14 128 ;;
    LD.MULT R1 LR0 CR10 ;;
{% for stage in range(2) %}
{% set nt = s0_tokens if stage == 0 else s3_tokens %}
{% set nb = (s1_n if stage == 0 else s4_n) // 128 %}
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ;;
    SET LR12 CR0 ; SET LR13 CR0 ;;
    INC LR12 {{nt // 128}} ; INC LR13 {{nb}} ;;
tokens{{stage}}:
    LD.MULT R0 LR2 {{cr.in0 if stage == 0 else cr.in1}} ;;
{% for k in range(8) %}
{% if stage == 0 %}
{% for sign in range(2) %}
    MULT.VE LR0 CR13 0 LR0 CR15.L CR14.L ; ACC.{{'ADD' if sign == 0 else 'SUB'}}.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 CR13 0 LR0 CR15.L CR14.L ; ACC.{{'SUB' if sign == 0 else 'ADD'}} ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu6 CR15.L CR14.L CR11 {{'LR0' if sign == 0 else 'LR11'}} ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR0 CR11 LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
    LD.MULT.CYCLIC LR11 CR11 LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L CR14.L CR12 LR3 ;;
{% else %}
{% for threshold in [k,k+1] %}
    MULT.VE LR0 CR13 0 LR0 CR15.L CR14.L ; ACC.SUB.FIRST ;;
{% for j in range(threshold) %}
    MULT.VE LR1 CR13 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu CR15.L CR14.L CR11 LR0 ;;
    LD.MULT.CYCLIC LR0 CR11 LR0 ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L CR14.L CR11 {{'LR11' if loop.first else 'LR0'}} ;;
{% endfor %}
    LD.MULT.CYCLIC LR11 CR11 LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR0 CR11 LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L CR14.L CR12 LR3 ;;
{% endif %}
    INC LR3 1 ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 tokens{{stage}} ;;
    SET LR2 CR0 ;;
block{{stage}}:
    SET LR4 CR0 ;;
lane{{stage}}:
    SET LR5 CR0 ;;
channel{{stage}}:
    SET LR6 LR2 ; SET LR7 LR5 ;;
{% if stage == 1 %}
    INC LR7 {{nb}} ;;
{% endif %}
{% for k in range(8) %}
    LD.MULT R0 LR6 CR12 ;;
    LD.MULT.CYCLIC LR7 {{cr.w0 if stage == 0 else cr.w1}} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L CR14.L ; ACC.ADD{{'.FIRST' if k == 0 else ''}} ;;
    INC LR6 1 ; INC LR7 {{nb}} ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L CR14.L {{cr.out0 if stage == 0 else cr.out1}} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 channel{{stage}} ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane{{stage}} ;;
    INC LR9 1 ; INC LR2 8 ;;
    BLT.S LR9 LR12 block{{stage}} ;;
{% endfor %}
    SET LR2 CR0 ; SET LR8 CR0 ; SET LR12 CR0 ;;
    SET LR13 CR0 ;;
    INC LR12 {{s6_tokens // 2}} ; INC LR13 {{s6_dim // 128}} ;;
    INC LR12 {{s6_tokens // 2}} ;;
fanout:
    SET LR5 CR0 ;;
fan_channel:
    LD.MULT.CYCLIC LR5 CR6 LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L CR14.L CR9 LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 fan_channel ;;
    INC LR2 1 ;;
    BLT.S LR2 LR12 fanout ;;
    HALT ;;
