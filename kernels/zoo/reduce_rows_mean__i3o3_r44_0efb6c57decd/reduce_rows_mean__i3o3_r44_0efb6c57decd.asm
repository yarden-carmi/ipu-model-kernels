{# Each channel occupies consecutive packed spatial rows. Scale only after summing. #}
{% set inv = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% set fp = format == 'fp32' %}
{% macro lane(src, dst) %}MULT.EE {{ src }} CR1 0 LR0 {{ cr.work }}.L {{ cr.qf_in0 }}.L ; AGG.SUM {{ dst }} {{ cr.one }}.L{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
channel:
    SET LR3 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.work if fp else cr.one }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% if fp %}
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 {{ cr.tail_slot }} ;;
{% endif %}
spatial:
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR3 1 ;;
{% if fp %}
    {# Match the FP32 reference's four interleaved eight-lane sums and scalar tail. #}
    SET LR4 CR0 ;;
width:
    BLT.S LR6 LR9 bulk ;;
    BGE.S LR6 LR10 tail ;;
    {{ lane('LR4', 'LR5') }} ;;
    INC.MODP2 LR5 CR1 3 ; BEQ LR0 CR0 next ;;
bulk:
    {{ lane('LR4', 'LR5') }} ;;
    INC.MODP2 LR5 CR1 5 ; BEQ LR0 CR0 next ;;
tail:
    {{ lane('LR4', 'LR7') }} ;;
next:
    INC LR4 1 ; INC LR6 1 ;;
    BLT.S LR4 {{ cr.packed_width }} width ;;
    INC LR1 1 ; BLT.S LR3 {{ cr.spatial }} spatial ;;
    ACTIVATE.QUANTIZE identity {{ cr.work }}.L {{ cr.qf_out0 }}.L {{ cr.partial }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.partial }} ; SET LR4 CR0 ;;
combine:
    SET LR5 LR4 ;;
    {% macro combine_part() %}
    INC LR5 8 ;;
    {{ lane('LR5', 'LR4') }} ;;
    {% endmacro %}
    {% for part in range(3) %}{{ combine_part() }}{% endfor %}
    INC LR4 1 ;;
    BLT.S LR4 LR8 combine ;;
    ACTIVATE.QUANTIZE identity {{ cr.work }}.L {{ cr.qf_out0 }}.L {{ cr.partial }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.partial }} ; SET LR4 CR0 ;;
    MULT.EE LR7 CR1 0 LR0 {{ cr.work }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
finish_sum:
    {{ lane('LR4', 'LR0') }} ;;
    INC LR4 1 ;;
    BLT.S LR4 LR8 finish_sum ;;
{% else %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 {{ cr.active }}.L ; INC LR1 1 ; BLT.S LR3 {{ cr.spatial }} spatial ;;
{% endif %}
    ACTIVATE.QUANTIZE identity {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.partial }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.partial }} ;;
    MULT.VE LR0 {{ inv }} 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.out0_d1 }} channel ;;
    HALT ;;
