{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set work = cr.scratch_qf ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set seed_q = cr.full ~ '.H' %}
{% set tail = cr.tail_qf ~ '.L' %}
{% set product_q = cr.tail_qf ~ '.H' %}
{% set ds = cr.out_tail_qf ~ '.L' %}
{% set norm_q = cr.out_tail_qf ~ '.H' %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro imm(reg,val) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ val }} ;;
{% endmacro %}
{# Split log2(e)/2 into coefficients representable even in the input format. #}
{% macro coefficient(power,count,slot) %}
{{ imm('LR1',7) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{% if power %}
{{ imm('LR6',power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ seed_q }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ slot }} ;;
{% endif %}
{{ imm('LR1',slot) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ seed_q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6',count) }}
count_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ seed_q }} ; ACC.ADD ; DEC LR6 1 ;;
    BNE LR6 CR0 count_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ;;
{{ imm('LR11',128) }}
    INC LR11 128 ;;
{{ imm('LR1',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ seed_q }} {{ cr.tmp }} LR1 ;;
{% for p,c,s in [(5,23,5),(13,21,6),(19,18,8),(26,19,9),(125,1,10),(0,80,11)] %}
{{ coefficient(p,c,s) }}
{% endfor %}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR11 ;;
    SET LR2 CR0 ;;

row:
{{ clear() }}
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ;;
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR5 CR0 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ; INC LR5 5 ;;
{% for slot in [5,6,8,9] %}
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ tail }} {{ q }} ; ACC.{% if loop.last %}SUB{% else %}ADD{% endif %}{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ tail }} {{ q }} ; ACC.{% if loop.last %}ADD{% else %}SUB ; INC LR5 {{ 2 if slot == 6 else 1 }}{% endif %} ;;
{% endfor %}
    MULT.RC.VE LR11 CR1 0 LR0 {{ tail }} {{ work }} ; ACC.MAX ; ACTIVATE.QUANTIZE exp2 {{ tail }} {{ root }} {{ cr.roots }} LR0 ;;
    ACTIVATE.QUANTIZE identity {{ tail }} {{ work }} {{ cr.norm }} LR2 ;;
    LD.MULT R0 LR2 {{ cr.norm }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ work }} ; ACC.SUB ; ADD LR5 LR2 {{ cr.rows }} ; ACTIVATE.QUANTIZE identity {{ tail }} {{ work }} {{ cr.norm }} LR5 ;;
{{ clear() }}
    LD.MULT.CYCLIC LR0 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ tail }} {{ root }} ; AGG.SUM LR0 {{ tail }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ; ADD LR5 LR5 {{ cr.rows }} ;;
    ACTIVATE.QUANTIZE rsqrt {{ full }} {{ norm_q }} {{ cr.norm }} LR5 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.rows }} row ;;

{# Scatter one source lane into the destination selected by LRD12. #}
{% macro scatter(index,fmt) %}MULT.EE {{ index }} CR1 0 LR0 {{ full }} {{ fmt }} ; ACC.RESHAPE LRD12 LRD12 7{% endmacro %}
{% macro gather(label,index,fmt) %}
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR5 LR14 ;;
{{ label }}_next:
    LD.MULT R0 LR4 {{ cr.norm }} ;;
    {{ scatter(index,fmt) }} ; INC LR4 1 ; DEC LR5 1 ;;
    ADDBI LRD12 1 ; BNE LR5 CR0 {{ label }}_next ;;
{% endmacro %}
    SET LR2 CR0 ; SET LR7 CR0 ; SET LR8 {{ cr.out0_d1 }} ;;
{{ imm('LR11',128) }}
head:
    SET LR3 LR7 ; SET LR10 CR0 ;;
column:
    ADD LR4 LR2 {{ cr.rows }} ;;
{{ gather('residual','LR10',work) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ; SET LR4 LR2 ;;
{{ gather('high','LR10',work) }}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
{{ imm('LR5',10) }}
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ norm_q }} {{ cr.tmp }} LR0 ;;
    BNE LR10 CR0 inverse_ready ;;
    ADD LR4 LR2 {{ cr.rows }} ;;
    ADD LR4 LR4 {{ cr.rows }} ;;
{{ gather('inverse','LR0',norm_q) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ norm_q }} {{ cr.roots }} LR0 ;;
inverse_ready:
    LD.MULT.CYCLIC LR0 {{ cr.roots }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ norm_q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ product_q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ product_q }} ; ACC.SUB ; SET LR5 CR1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ product_q }} {{ cr.tmp }} LR5 ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR11 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ product_q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
{% for i in range(2) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ product_q }} ; ACC.ADD ;;
{% endfor %}
    MULT.RC.VS LR11 0 LR0 {{ ds }} {{ product_q }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR3 ;;
    ADD LR3 LR3 {{ cr.out0_d1 }} ; INC LR10 1 ;;
    BLT.S LR10 LR15 column ;;
    ADD LR2 LR2 LR14 ; DEC LR8 1 ;;
    BEQ LR8 CR0 next_batch ;;
    INC LR7 1 ; B head ;;
next_batch:
    INC LR3 1 ;;
    SET LR7 LR3 ; SET LR8 {{ cr.out0_d1 }} ;;
    SET LR5 {{ cr.out0_d1 }} ; SUB LR7 LR7 LR5 ;;
    BLT.S LR2 {{ cr.rows }} head ;;
    HALT ;;
