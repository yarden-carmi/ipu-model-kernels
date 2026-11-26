{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set work = cr.scratch_qf ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set ds = cr.active ~ '.L' %}
{% set centered = cr.active ~ '.H' %}
{% set od = cr.out_ds ~ '.L' %}
{% set lo = cr.out_ds ~ '.H' %}
{% set hi = cr.full ~ '.H' %}
{% set act = act_out0 | default('identity') %}
{% macro imm(reg,val) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ val }} ;;
{% endmacro %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{# Synthesize dyadic coefficients for log2(e)/2 and the root phase spacing. #}
{% macro coefficient(power,count,slot) %}
    LD.MULT R0 LR9 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6',power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ slot }} ;;
{{ imm('LR1',slot) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6',count) }}
count_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; DEC LR6 1 ;;
    BNE LR6 CR0 count_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ centered if slot in [5,6] else q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}
{% macro weights(reduce) %}
    SET LR5 CR0 ;;
{% for phase in range(8) %}
    LD.MULT.CYCLIC LR5 {{ cr.roots }} LR12 ;;
    MULT.RC.VS LR12 0 LR0 {{ ds }} {{ root }} ; {% if reduce %}AGG.SUM{% else %}ACC.ADD{% endif %}{% if loop.first %}.FIRST{% endif %}{% if reduce %} LR0 {{ ds }}{% endif %}{% if not loop.last %} ; INC LR5 1{% endif %} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ;;
{{ imm('LR10',128) }}
    ADD LR11 LR10 LR10 ;;
    ADD LR13 LR11 LR10 ; SET LR12 CR0 ;;
{{ imm('LR9',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR9 ;;
{{ coefficient(5,23,5) }}
{{ coefficient(13,21,6) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR13 ;;
{{ coefficient(3,1,8) }}
    SET LR6 LR1 ;;
    LD.MULT R0 LR9 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR5',32) }}
make_floor:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR5 1 ;;
    BNE LR5 CR0 make_floor ;;
{{ imm('LR5',10) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ centered }} {{ cr.tmp }} LR5 ;;
{{ imm('LR8',5) }}

row:
    LD.MULT.CYCLIC LR8 {{ cr.tmp }} LR0 ;;
{{ imm('LR5',10) }}
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR11 ;;
{{ clear() }}
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR1 CR1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.MAX.FIRST LR0 {{ ds }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.VE LR10 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
    MULT.RC.VE LR11 CR1 0 LR0 {{ ds }} {{ centered }} ; ACC.MAX ; ACTIVATE.QUANTIZE identity {{ ds }} {{ centered }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ centered }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ centered }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{% for coeff in ['LR0','LR13'] %}
    MULT.RC.VV {{ coeff }} R0 0 LR0 {{ ds }} {{ centered }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV {{ coeff }} R1 0 LR0 {{ ds }} {{ centered }} ; ACC.ADD{% if loop.last %} ; LD.MULT R0 LR6 {{ cr.tmp }}{% endif %} ;;
{% endfor %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR0 ; SET LR5 CR1 ;;
{% for phase in range(7) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR5 ;;
{% if not loop.last %}
    INC LR5 1 ;;
{% endif %}
{% endfor %}

{# Averaging eight squared roots reduces exponent quantization error. #}
{{ weights(true) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ;;
    MULT.EE LR10 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE reciprocal {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
    LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR12 ;;
    MULT.RC.VE LR12 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR10 LR0 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    MULT.RC.VE LR10 LR10 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
    MULT.RC.VS LR12 0 LR0 {{ full }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;

{{ weights(false) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ; LD.MULT R1 LR0 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR12 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; ADD LR5 LR2 LR7 ;;
    MULT.RC.VV LR12 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ ds }} {{ hi }} CR0 LR5 ;;
    LD.MULT R0 LR5 CR0 ;;
    ADD LR5 LR5 {{ cr.rows }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ hi }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ lo }} CR0 LR5 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.rows }} row ;;

{# Reassemble each column from row vectors, keeping the rounding residual
   until the output-format store. Visit memory in batch, column, head order. #}
{% macro gather(label,fmt) %}
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR5 {{ cr.out0_d2 }} ;;
{{ label }}:
    LD.MULT R0 LR4 CR0 ;;
    MULT.EE LR10 CR1 0 LR0 {{ full }} {{ fmt }} ; ACC.RESHAPE LRD12 LRD12 7 ; INC LR4 1 ; DEC LR5 1 ;;
    ADDBI LRD12 1 ; BNE LR5 CR0 {{ label }} ;;
{% endmacro %}
    SET LR2 LR7 ; SET LR3 CR0 ; ADD LR1 LR7 {{ cr.rows }} ;;
batch:
    SET LR10 CR0 ;;
column:
    SET LR11 LR2 ; SET LR8 {{ cr.out0_d1 }} ;;
head:
    ADD LR4 LR11 {{ cr.rows }} ;;
{{ gather('gather_lo',lo) }}
    ACTIVATE.QUANTIZE identity {{ od }} {{ lo }} {{ cr.tmp }} LR0 ; SET LR4 LR11 ;;
{{ gather('gather_hi',hi) }}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ od }} {{ lo }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ 'relu' if act == 'identity' else act }} {{ od }} {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; SET LR11 LR4 ; DEC LR8 1 ;;
    BNE LR8 CR0 head ;;
    INC LR10 1 ;;
    BLT.S LR10 LR15 column ;;
    ADD LR2 LR2 {{ cr.batch_rows }} ;;
    BLT.S LR2 LR1 batch ;;
    HALT ;;
