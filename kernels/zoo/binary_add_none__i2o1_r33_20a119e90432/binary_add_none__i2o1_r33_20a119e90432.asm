{% macro add_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.op0_const0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_op0_const0 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
    INC LR2 128 ;;
block:
{% for k in range(11) %}{{ add_row('CR15.L') }}{% endfor %}
{{ add_row(cr.tail ~ '.L') }}
    INC LR3 1 ; BLT.S LR3 {{ cr.rows }} block ;;
    HALT ;;
