{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set work = cr.scratch_qf ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set act = act_out0 | default('identity') %}
{% set highq = cr.full ~ '.H' %}
{% macro imm(reg,val) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ val }} ;;
{% endmacro %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
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
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ;;
{{ imm('LR10',128) }}
    ADD LR13 LR10 LR10 ;;
    ADD LR13 LR13 LR10 ; SET LR12 CR0 ;;
{{ imm('LR9',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR9 ;;
{{ coefficient(5,23,5) }}
{{ coefficient(13,21,6) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR13 ;;
{{ coefficient(3,1,8) }}
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;
{% macro scan(label) %}
    SET LR4 LR2 ; SET LR3 CR0 ;;
    BEQ LR8 CR0 {{ label }}_tail ;;
{{ label }}_full:
{{ caller(full, false) }}
    INC LR3 1 ;;
    BLT.S LR3 LR8 {{ label }}_full ;;
{{ label }}_tail:
{{ caller(tail, true) }}
{% endmacro %}
{% macro maximum(ds,first) %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.MAX{% if first %}.FIRST{% endif %} LR0 {{ ds }} ; INC LR4 1 ;;
{% endmacro %}
row:
{{ imm('LR6',5) }}
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
{{ imm('LR6',8) }}
{{ clear() }}
    SET LR4 LR2 ; BEQ LR8 CR0 max_single ;;
{{ maximum(full,true) }}
    SET LR3 CR1 ;;
    BEQ LR3 LR8 max_tail ;;
max_full:
{{ maximum(full,false) }}
    INC LR3 1 ;;
    BLT.S LR3 LR8 max_full ;;
max_tail:
{{ maximum(tail,false) }}
    B max_ready ;;
max_single:
{{ maximum(tail,true) }}
max_ready:
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{% call(ds,last) scan('exp') %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
{% for coeff in ['LR0','LR13'] %}
    MULT.RC.VV {{ coeff }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV {{ coeff }} R1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB{% if loop.last %} ; LD.MULT R0 LR6 {{ cr.tmp }}{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3 ; ADD LR5 LR3 {{ cr.K }} ; INC LR4 1 ;;
{% for phase in range(7) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR5 ;;
{% if not loop.last %}
    ADD LR5 LR5 {{ cr.K }} ;;
{% endif %}
{% endfor %}
{% endcall %}
{% macro weights(ds,reduce=false,last=false) %}
    SET LR5 LR3 ;;
{% for phase in range(8) %}
    LD.MULT.CYCLIC LR5 {{ cr.roots }} LR12 ;;
    MULT.RC.VS LR12 0 LR0 {{ ds }} {{ root }} ; {% if reduce %}AGG.SUM LR0 {{ ds }}{% else %}ACC.ADD{% if loop.first %}.FIRST{% endif %}{% endif %}{% if loop.last and last %} ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0{% elif not loop.last %} ; ADD LR5 LR5 {{ cr.K }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{{ clear() }}
{% call(ds,last) scan('sum') %}
{{ weights(ds,true,last) }}
{% endcall %}
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
{% call(ds,last) scan('normalize') %}
{{ weights(ds) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exps }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exps }} LR3 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.exps }} ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR12 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; ADD LR5 LR4 LR7 ;;
    MULT.RC.VV LR12 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ ds }} {{ highq }} CR0 LR5 ;;
    INC LR4 1 ;;
{% endcall %}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row ;;
{% macro scatter(fmt) %}MULT.EE LR10 CR1 0 LR0 {{ full }} {{ fmt }} ; ACC.RESHAPE LRD12 LRD12 7{% endmacro %}
{% macro gather(label,fmt) %}
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR5 LR6 ;;
    LD.MULT R0 LR4 CR0 ; DEC LR5 1 ; BEQ LR5 CR1 {{ label }}_last ;;
    LD.MULT R0 LR4 CR0 ; {{ scatter(fmt) }} ; ADD LR4 LR4 {{ cr.K }} ; DEC LR5 1 ; BEQ LR5 CR1 {{ label }}_advance ;;
{{ label }}_next:
    LD.MULT R0 LR4 CR0 ; {{ scatter(fmt) }} ; ADD LR4 LR4 {{ cr.K }} ; DEC LR5 1 ; ADDBI LRD12 1 ; BNE LR5 CR1 {{ label }}_next ;;
{{ label }}_advance:
    ADDBI LRD12 1 ;;
{{ label }}_last:
    {{ scatter(fmt) }} ; ADD LR4 LR4 {{ cr.K }} ;;
{% endmacro %}
{% macro emit(label,ds) %}
{{ gather(label ~ '_hi',highq) }}
    ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endmacro %}
    SET LR2 LR7 ; SET LR3 CR0 ; ADD LR1 LR7 {{ cr.M }} ;;
transpose_batch:
    SET LR10 CR0 ; SET LR9 CR0 ; SET LR7 CR0 ;;
transpose_column:
    ADD LR4 LR2 LR7 ; SET LR8 LR14 ; SET LR6 CR0 ;;
    INC LR6 128 ;;
    BLE.S LR8 LR6 transpose_tail ;;
transpose_tile:
{{ emit('full_gather',full) }}
    DEC LR8 128 ;;
    BLT.S LR6 LR8 transpose_tile ;;
transpose_tail:
    SET LR6 LR8 ;;
{{ emit('tail_gather',cr.out_tail ~ '.L') }}
    INC LR9 1 ; INC LR10 1 ;;
    BEQ LR9 LR15 transpose_next_batch ;;
    SET LR6 CR0 ;;
    INC LR6 128 ;;
    BLT.S LR10 LR6 transpose_column ;;
    SET LR10 CR0 ; INC LR7 1 ; B transpose_column ;;
transpose_next_batch:
    ADD LR2 LR2 {{ cr.row_group }} ;;
    BLT.S LR2 LR1 transpose_batch ;;
    HALT ;;
