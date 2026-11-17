    INC LR1 128 ; INC LR11 1 ; INC LR14 128 ;;
    LD.MULT R1 LR0 CR5 ;;
{% for stage in range(2) %}
{% set vocab = s0_vocab if stage == 0 else s4_vocab %}
{% set ke = [vocab, 8 if stage == 0 else 9] | min %}
{% set ntb = (s0_tokens if stage == 0 else s4_tokens) // 128 %}
{% set nb = (s1_n if stage == 0 else s5_n) // 128 %}
{% set inp = 'CR2' if stage == 0 else 'CR11' %}
{% set weight = 'CR3' if stage == 0 else 'CR12' %}
{% set output = 'CR8' if stage == 0 else 'CR13' %}
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ;;
    SET LR12 CR0 ; SET LR13 CR0 ;;
    INC LR12 {{ntb}} ; INC LR13 {{nb}} ;;
tokens{{stage}}:
    LD.MULT R0 LR2 {{inp}} ;;
{% for k in range(ke) %}
{% set delta = k - stage %}
{% for sign in ['ADD','SUB'] %}
    MULT.VE LR0 CR9 0 LR0 CR15.L CR10.L ; ACC.{{sign}}.FIRST ;;
{% for j in range(delta | abs) %}
    MULT.VE LR1 CR9 0 LR0 CR15.L CR10.L ; ACC.{{ ('SUB' if sign == 'ADD' else 'ADD') if delta >= 0 else sign }} ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu6 CR15.L CR10.L CR6 {{'LR0' if sign == 'ADD' else 'LR11'}} ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L CR10.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR0 CR6 LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR10.L ; ACC.SUB ;;
    LD.MULT.CYCLIC LR11 CR6 LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR10.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L CR10.L CR7 LR3 ;;
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
{% for k in range(ke) %}
    LD.MULT R0 LR6 CR7 ;;
    LD.MULT.CYCLIC LR7 {{weight}} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L CR10.L ; ACC.ADD{{'.FIRST' if k == 0 else ''}} ;;
    INC LR6 1 ; INC LR7 {{nb}} ;;
{% endfor %}
{% if stage == 0 and s1_bias %}
    LD.MULT R1 LR5 CR4 ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L CR10.L ; ACC.ADD ;;
{% else %}
    MULT.VE LR1 CR1 0 LR0 CR15.L CR10.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L CR10.L ; ACC.SUB ;;
{% endif %}
    ACTIVATE.QUANTIZE identity CR15.L CR10.L {{output}} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 channel{{stage}} ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane{{stage}} ;;
    INC LR9 1 ; INC LR2 {{ke}} ;;
    BLT.S LR9 LR12 block{{stage}} ;;
    LD.MULT R1 LR0 CR5 ;;
{% endfor %}
    SET LR2 CR0 ; SET LR12 CR0 ;;
    INC LR12 {{s8_m // 2}} ;;
    INC LR12 {{s8_m // 2}} ;;
last:
{% for c in range(s8_n // 128) %}
    SET LR7 CR0 ;;
    INC LR7 {{c}} ;;
    LD.MULT R0 LR7 CR14 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L CR10.L ; ACC.ADD.FIRST ;;
{% if s8_bias %}
    SET LR6 LR10 ;;
    INC LR6 {{c}} ;;
    LD.MULT R0 LR6 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L CR10.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE identity CR15.L CR10.L CR0 LR15 ;;
    INC LR15 1 ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 last ;;
    HALT ;;
