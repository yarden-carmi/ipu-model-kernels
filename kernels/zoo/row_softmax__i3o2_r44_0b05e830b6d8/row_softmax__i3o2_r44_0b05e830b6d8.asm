{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set work = cr.scratch_qf ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set high = cr.full ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% set out_ds = cr.tail ~ '.H' %}
{% set scalar = cr.scalar ~ '.L' %}
{% set low = cr.scalar ~ '.H' %}
{% macro imm(r,v) %}
    SET {{ r }} CR0 ;;
    INC {{ r }} {{ v }} ;;
{% endmacro %}
{% macro zero() %}MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST{% endmacro %}
{% macro coefficient(power,num,slot) %}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    {{ zero() }} ;;
{{ imm('LR1',power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR1 1 ;;
    BNE LR1 CR0 power_{{ slot }} ;;
{{ imm('LR3',slot) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.tmp }} ;;
    {{ zero() }} ;;
{{ imm('LR1',num) }}
num_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; DEC LR1 1 ;;
    BNE LR1 CR0 num_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR3 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ;;
    {{ zero() }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
{{ coefficient(5,23,1) }}
{{ coefficient(13,21,2) }}
{{ coefficient(3,1,3) }}
{{ imm('LR8',128) }}
    ADD LR9 LR8 LR8 ;;
    LD.MULT.CYCLIC LR3 {{ cr.tmp }} LR9 ; SET LR7 LR3 ;;
    INC LR3 3 ;;
{{ imm('LR5',2) }}
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR8 ; SET LR1 CR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    ADD LR10 LR8 LR9 ; SUB LR11 LR15 CR1 ;;

row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR4 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ; ACTIVATE.QUANTIZE identity {{ scalar }} {{ q }} {{ cr.tmp }} LR3 ;;
    LD.MULT R1 LR3 {{ cr.tmp }} ;;
{% for coeff in ['LR0','LR8'] %}
    MULT.RC.VV {{ coeff }} R0 0 LR0 {{ tail }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE {{ coeff }} LR8 0 LR0 {{ tail }} {{ q }} ; ACC.SUB ;;
{% endfor %}
{# Sample eight scales over one octave to reduce quantization bias. #}
{% for i in range(8) %}
    MULT.RC.VE LR9 CR1 0 LR0 {{ tail }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ tail }} {{ root }} {{ cr.roots }} LR4{% if not loop.first %} ; INC LR4 1{% endif %} ;;
{% endfor %}
{% macro weights(reduce) %}
    SET LR4 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.roots }} LR10 ;;
{% for i in range(8) %}
    MULT.RC.VS LR10 0 LR0 {{ tail }} {{ root }} ; {% if reduce %}AGG.SUM{% else %}ACC.ADD{% endif %}{% if loop.first %}.FIRST{% endif %}{% if reduce %} LR0 {{ tail }}{% endif %}{% if not loop.last %} ; LD.MULT.CYCLIC LR4 {{ cr.roots }} LR10 ; INC LR4 1{% endif %} ;;
{% endfor %}
{% endmacro %}
{{ weights(true) }}
{# Refine the reciprocal with one Newton correction, keeping the sum residual. #}
    ACTIVATE.QUANTIZE identity {{ scalar }} {{ work }} {{ cr.tmp }} LR4 ;;
    ACTIVATE.QUANTIZE reciprocal {{ scalar }} {{ work }} {{ cr.tmp }} LR5 ; LD.MULT R0 LR4 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ scalar }} {{ work }} {{ cr.tmp }} LR3 ; LD.MULT R1 LR5 {{ cr.tmp }} ;;
    MULT.EE LR8 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR5 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR10 ;;
    LD.MULT R1 LR3 {{ cr.tmp }} ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR9 ;;
    MULT.RC.VE LR9 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR10 LR0 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    MULT.RC.VE LR10 LR8 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.tmp }} ;;
    MULT.RC.VE LR10 LR0 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR3 ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR9 ;;
{{ weights(false) }}
    ACTIVATE.QUANTIZE identity {{ tail }} {{ work }} {{ cr.tmp }} LR4 ;;
    LD.MULT R0 LR4 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ tail }} {{ work }} {{ cr.tmp }} LR4 ; LD.MULT.CYCLIC LR3 {{ cr.tmp }} LR10 ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ tail }} {{ work }} ; ACC.ADD.FIRST ; LD.MULT R1 LR4 {{ cr.tmp }} ;;
    MULT.RC.VV LR9 R1 0 LR0 {{ tail }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ tail }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ tail }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ tail }} {{ high }} CR0 LR11 ; INC LR11 1 ; INC LR2 1 ;;
    LD.MULT R0 LR11 CR0 ; ADD LR12 LR11 {{ cr.M }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ high }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ tail }} {{ low }} CR0 LR12 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR9 ;;
    BLT.S LR2 {{ cr.M }} row ;;

{% macro scatter(fmt) %}MULT.EE LR10 CR1 0 LR0 {{ full }} {{ fmt }} ; ACC.RESHAPE LRD12 LRD12 7{% endmacro %}
{% macro gather(tag,fmt,offset) %}
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR5 {{ cr.out0_d2 }} ;;
    {{ offset }} ;;
    LD.MULT R0 LR4 CR0 ; BEQ LR5 CR1 {{tag}}_last ;;
    LD.MULT R0 LR4 CR0 ; {{ scatter(fmt) }} ; INC LR4 1 ; DEC LR5 1 ; BEQ LR5 LR6 {{tag}}_advance ;;
{{tag}}_loop:
    LD.MULT R0 LR4 CR0 ; {{ scatter(fmt) }} ; INC LR4 1 ; DEC LR5 1 ; ADDBI LRD12 1 ; BNE LR5 LR6 {{tag}}_loop ;;
{{tag}}_advance:
    ADDBI LRD12 1 ;;
{{tag}}_last:
    {{ scatter(fmt) }} ;;
{% endmacro %}
    SET LR2 LR15 ; SET LR3 CR0 ; SET LR0 CR0 ;;
{{ imm('LR6',2) }}
transpose_batch:
    SET LR10 CR0 ;;
transpose_column:
    SET LR8 LR2 ; SET LR11 CR0 ;;
transpose_head:
{{ gather('lo',low,'ADD LR4 LR8 ' ~ cr.M) }}
    ACTIVATE.QUANTIZE identity {{ out_ds }} {{ low }} {{ cr.tmp }} LR0 ;;
{{ gather('hi',high,'SET LR4 LR8') }}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ out_ds }} {{ low }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ out_ds }} {{ qo }} {{ cr.out0 }} LR3 ; ADD LR8 LR8 {{ cr.out0_d2 }} ; INC LR11 1 ;;
    INC LR3 1 ;;
    BLT.S LR11 {{ cr.out0_d1 }} transpose_head ;;
    INC LR10 1 ; BLT.S LR10 {{ cr.n_minus_one }} transpose_column ;;
    SET LR2 LR8 ; BLT.S LR3 {{ cr.M }} transpose_batch ;;
    HALT ;;
