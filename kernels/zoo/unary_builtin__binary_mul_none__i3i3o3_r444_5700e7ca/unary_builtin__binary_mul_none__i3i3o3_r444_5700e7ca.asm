{% set chunks = (out0_d3 + 127) // 128 %}
{% macro st(act, ds, lr) %}; ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ lr }}{% endmacro %}
{% macro ar(s, a, ds, qf=cr.qf_in0) %}MULT.VE LR0 {{ s }} 0 LR0 {{ ds }} {{ qf }}.L ; ACC.{{ a }}{% endmacro %}
{% macro prepare(ds, tail) %}
    LD.MULT R0 LR1 {{ cr.in1 }} ;;
    {{ ar('CR1','SUB.FIRST',ds,cr.qf_in1) }} ;;
    {{ ar('CR1','MAX',ds,cr.qf_in1) }} {{ st('identity',ds,'LR8') }} ;;
    LD.MULT R0 LR8 {{ cr.s0 }} ;;
    {{ ar('CR0','ADD.FIRST',ds,cr.qf_in1) }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; AGG.MAX.FIRST LR0 {{ ds }} {{ st('relu',ds,'LR8') }} ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    LD.MULT R1 LR8 {{ cr.s0 }} ;;
    {{ ar('CR1','ADD.FIRST',ds,cr.qf_in1) }} ;;
    {{ ar('CR1','ADD',ds,cr.qf_in1) }} ;;
    MULT.EE LR10 {{ cr.floor_scale }} 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD {{ st(act_s0,ds,'LR1') }} ; LD.MULT R1 LR3 {{ cr.s0 }} ;;
    ADD LR7 LR1 LR12 ; {{ ar(cr.factor,'ADD.FIRST',ds,cr.qf_in1) }} {% if not tail %}{{ st(act_s0,ds,'LR7') }}{% endif %};;
{% if tail %}
    MULT.EE LR10 {{ cr.anchor }} 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD10 7 {{ st(act_s0,cr.full~'.L','LR7') }} ;;
{% endif %}
    LD.MULT R0 LR7 {{ cr.s0 }} ;;
{% for acc, slot in [('ADD.FIRST','LR8'),('SUB.FIRST','LR9')] %}
    {{ ar('CR1',acc,ds) }} ;;
    MULT.EE LR10 {{ cr.zero_threshold }} 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.SUB {% if not tail %}{{ st('relu6',ds,slot) }}{% endif %};;
{% if tail %}
    MULT.EE LR10 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD10 7 {{ st('relu6',cr.full~'.L',slot) }} ;;
{% endif %}
{% endfor %}
    LD.MULT R0 LR8 {{ cr.s0 }} ;;
    {{ ar(cr.restore,'ADD.FIRST',ds) }} ; LD.MULT R0 LR9 {{ cr.s0 }} ;;
    {{ ar(cr.restore,'SUB',ds) }} {{ st('identity',ds,'LR7') }} ;;
    LD.MULT R0 LR7 {{ cr.s0 }} ;;
    {{ ar(cr.anchor,'SUB.FIRST',ds) }} ;;
    {{ ar(cr.anchor,'MAX',ds) }} {{ st('relu6',ds,'LR8') }} ;;
    LD.MULT R0 LR8 {{ cr.s0 }} ;;
    {{ ar(cr.floor_scale,'ADD.FIRST',ds) }} ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    {{ ar('CR1','ADD',ds,cr.qf_in1) }} ;;
    {{ ar('CR1','ADD',ds,cr.qf_in1) }} {{ st(act_s0,ds,'LR1') }} ;;
    INC LR1 1 ;;
{% endmacro %}
{% macro output(ds) %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR7 LR1 LR12 ;;
{% for a, slot in [('ADD','LR8'),('SUB','LR9')] %}
    {{ ar(cr.sign_scale,a~'.FIRST',ds) }} {% if loop.first %}; LD.MULT.CYCLIC LR1 {{ cr.s0 }} LR0 {% endif %};;
{% for j in range(4) %}
    {{ ar(cr.sign_scale,a,ds) }} ;;
{% endfor %}
    {{ ar(cr.sign_scale,a,ds) }} {{ st('relu6',ds,slot) }} ;;
{% endfor %}
    LD.MULT R0 LR8 {{ cr.s0 }} ;;
    {{ ar('CR1','ADD.FIRST',ds) }} ; LD.MULT R0 LR9 {{ cr.s0 }} ;;
    {{ ar('CR1','SUB',ds) }} {{ st('identity',ds,'LR8') }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR7 {{ cr.s0 }} LR0 ; INC LR1 1 ;;
    LD.MULT R0 LR8 {{ cr.s0 }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
{% endmacro %}
    ADD LR8 LR12 LR12 ; INC LR10 128 ;;
    ADD LR9 LR8 CR1 ; MULT.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ADD LR3 LR9 CR1 {{ st('exp2',cr.full~'.L','LR3') }} ;;
    LD.MULT R1 LR3 {{ cr.s0 }} ;;
batch:
    SET LR4 LR1 ; ADD LR5 LR1 LR13 ;;
prep:
{% for i in range(chunks) %}
    {{ prepare(cr.full~('.H' if i == chunks-1 else '.L'), i == chunks-1 and out0_d3 % 128 != 0) }}
{% endfor %}
    BLT.S LR1 LR5 prep ;;
    SET LR6 LR15 ;;
channel:
    SET LR1 LR4 ;;
row:
{% for i in range(chunks) %}
    {{ output(cr.full~('.H' if i == chunks-1 else '.L')) }}
{% endfor %}
    BLT.S LR1 LR5 row ;;
    DEC LR6 1 ; BLT.S CR1 LR6 channel ;;
    BLT.S LR2 LR14 batch ;;
    HALT ;;
