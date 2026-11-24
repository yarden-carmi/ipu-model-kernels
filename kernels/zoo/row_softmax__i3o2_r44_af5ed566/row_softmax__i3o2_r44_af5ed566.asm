{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set row_ds = cr.row_ds ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set work = cr.scratch_qf ~ '.H' %}
{% set product_q = cr.row_ds ~ '.H' %}
{% set out_tail = cr.out_ds ~ '.L' %}
{% set norm_q = cr.out_ds ~ '.H' %}
{% macro imm(reg,val) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ val }} ;;
{% endmacro %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}

{# Generate dyadic pieces of log2(e)/2 and the exponent floor. #}
{% macro coefficient(power,count,slot) %}
{{ imm('LR1',7) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{% if power %}
{{ imm('LR6',power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ slot }} ;;
{% endif %}
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
    SET LR0 CR0 ;;
{{ imm('LR11',128) }}
    INC LR11 128 ;;
{{ imm('LR1',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% for p,c,s in [(5,23,5),(13,21,6),(19,18,8),(26,19,9),(110,1,10),(0,80,11)] %}
{{ coefficient(p,c,s) }}
{% endfor %}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR11 ;;
    SET LR2 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;

{# LR8 selects the packed DRAM row; LR7 selects the logical row within it. #}
softmax_row:
{{ clear() }}
    LD.MULT R0 LR8 {{ cr.in0 }} ; SET LR1 CR1 ;;
    MULT.VE LR7 CR1 0 LR0 {{ row_ds }} {{ q }} ; AGG.MAX.FIRST LR0 {{ row_ds }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{{ imm('LR10',128) }}
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR10 ; SET LR5 CR0 ; ADD LR9 LR10 LR7 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ; INC LR5 5 ;;
{% for slot in [5,6,8,9] %}
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
    INC LR5 {{ 2 if slot == 6 else 1 }} ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ row_ds }} {{ q }} ; ACC.{% if loop.last %}SUB{% else %}ADD{% endif %}{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ row_ds }} {{ q }} ; ACC.{% if loop.last %}ADD{% else %}SUB{% endif %} ;;
{% endfor %}
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ row_ds }} {{ q }} ; ACC.SUB ;;
    MULT.RC.VE LR11 CR1 0 LR0 {{ row_ds }} {{ work }} ; ACC.MAX ; ACTIVATE.QUANTIZE exp2 {{ row_ds }} {{ root }} {{ cr.roots }} LR0 ;;
    ACTIVATE.QUANTIZE identity {{ row_ds }} {{ work }} {{ cr.norm }} LR2 ;;
    LD.MULT R0 LR2 {{ cr.norm }} ; ADD LR4 LR2 {{ cr.rows }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ row_ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ row_ds }} {{ work }} {{ cr.norm }} LR4 ;;

{{ clear() }}
    LD.MULT.CYCLIC LR0 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ row_ds }} {{ root }} ; AGG.SUM.FIRST LR0 {{ row_ds }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ; ADD LR4 LR4 {{ cr.rows }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ norm_q }} {{ cr.norm }} LR4 ;;
    INC LR2 1 ; ADD LR7 LR7 LR15 ;;
    BEQ LR2 {{ cr.rows }} transpose_start ;;
    BLT.S LR7 {{ cr.width }} softmax_row ;;
    INC LR8 1 ; SET LR7 CR0 ; B softmax_row ;;

{# Gather a column from each scratch plane. Reshape writes one lane at a time. #}
{% macro scatter(index,fmt) %}MULT.EE {{ index }} CR1 0 LR0 {{ full }} {{ fmt }} ; ACC.RESHAPE LRD12 LRD12 7{% endmacro %}
{% macro gather(label,index,fmt) %}
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR5 LR6 ;;
    LD.MULT R0 LR4 {{ cr.norm }} ; DEC LR5 1 ; BEQ LR5 CR1 {{ label }}_single ;;
    LD.MULT R0 LR4 {{ cr.norm }} ; {{ scatter(index,fmt) }} ; ADD LR4 LR4 CR1 ; DEC LR5 1 ; BEQ LR5 CR1 {{ label }}_last ;;
{{ label }}_next:
    LD.MULT R0 LR4 {{ cr.norm }} ; {{ scatter(index,fmt) }} ; ADD LR4 LR4 CR1 ; DEC LR5 1 ; ADDBI LRD12 1 ; BNE LR5 CR1 {{ label }}_next ;;
{{ label }}_last:
    ADDBI LRD12 1 ;;
{{ label }}_single:
    {{ scatter(index,fmt) }} ; ADD LR4 LR4 CR1 ;;
{% endmacro %}
{% macro transpose(label,ds) %}
    SET LR1 LR4 ;;
    ADD LR4 LR1 {{ cr.rows }} ;;
{{ gather(label ~ '_residual','LR10',work) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    SET LR4 LR1 ;;
{{ gather(label ~ '_high','LR10',work) }}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
{{ imm('LR5',10) }}
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ norm_q }} {{ cr.tmp }} LR0 ;;
    ADD LR4 LR1 {{ cr.rows }} ;;
    ADD LR4 LR4 {{ cr.rows }} ;;
{{ gather(label ~ '_inverse','LR0',norm_q) }}
    SET LR5 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ norm_q }} {{ cr.tmp }} LR5 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ norm_q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ product_q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ product_q }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ product_q }} {{ cr.tmp }} LR5 ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR11 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ product_q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
{% for i in range(2) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ product_q }} ; ACC.ADD ;;
{% endfor %}
    MULT.RC.VS LR11 0 LR0 {{ ds }} {{ product_q }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; SUB LR4 LR4 {{ cr.rows }} ;;
    SUB LR4 LR4 {{ cr.rows }} ;;
{% endmacro %}

transpose_start:
    SET LR2 CR0 ; SET LR3 CR0 ;;
{{ imm('LR11',128) }}
transpose_batch:
    SET LR10 CR0 ;;
transpose_column:
    SET LR4 LR2 ; SET LR8 {{ cr.out0_d2 }} ; SET LR6 LR11 ;;
    BLE.S LR8 LR11 transpose_tail ;;
transpose_tile:
{{ transpose('gather_full',full) }}
    DEC LR8 128 ;;
    BLT.S LR11 LR8 transpose_tile ;;
transpose_tail:
    SET LR6 LR8 ;;
{{ transpose('gather_tail',out_tail) }}
    INC LR10 1 ;;
    BLT.S LR10 LR14 transpose_column ;;
    ADD LR2 LR2 {{ cr.out0_d2 }} ;;
    BLT.S LR2 {{ cr.rows }} transpose_batch ;;
    HALT ;;
