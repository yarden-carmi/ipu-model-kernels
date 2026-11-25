{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set work = cr.scratch_qf ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set seed_q = cr.full ~ '.H' %}
{% set tail = cr.tail_qf ~ '.L' %}
{% set product_q = cr.tail_qf ~ '.H' %}
{% set out_tail = cr.out_tail_qf ~ '.L' %}
{% set norm_q = cr.out_tail_qf ~ '.H' %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro imm(reg,val) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ val }} ;;
{% endmacro %}
{% macro tiles(label) %}
    SET LR3 CR0 ;;
    BEQ LR3 LR8 {{ label }}_tail ;;
{{ label }}_loop:
{{ caller(full) }}
    INC LR3 1 ;;
    BLT.S LR3 LR8 {{ label }}_loop ;;
{{ label }}_tail:
{{ caller(tail) }}
{% endmacro %}

{# Generate dyadic seeds in the fork's fixed scratch format, then convert
   the coefficients to the input format for the mixed products. #}
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
{{ imm('LR13',128) }}
    SET LR11 LR13 ; SET LR10 LR13 ;;
    INC LR11 128 ;;
{{ imm('LR1',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ seed_q }} {{ cr.tmp }} LR1 ;;
{% for p,c,s in [(5,23,5),(13,21,6),(19,18,8),(26,19,9)] %}
{{ coefficient(p,c,s) }}
{% endfor %}
{{ coefficient(125,1,10) }}
{{ coefficient(0,80,11) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR11 ;;
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;
    SET LR2 CR0 ;;

row:
    SET LR4 LR2 ;;
{{ clear() }}
    LD.MULT R0 LR4 {{ cr.in0 }} ; BEQ LR8 CR0 max_single ;;
{% macro max_reduce(ds, first=false) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.MAX{% if first %}.FIRST{% endif %} LR0 {{ ds }} ;;
{% endmacro %}
{{ max_reduce(full,true) }}
    SET LR3 CR0 ;;
max_next:
    INC LR4 1 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR3 1 ;;
    BEQ LR3 LR8 max_tail ;;
{{ max_reduce(full) }}
    B max_next ;;
max_tail:
{{ max_reduce(tail) }}
    B max_ready ;;
max_single:
{{ max_reduce(tail,true) }}
max_ready:
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; SET LR4 LR2 ;;
    DEC LR4 1 ;;
{% call(ds) tiles('exponentiate') %}
    LD.MULT R0 LR4 {{ cr.in0 }} ; SET LR5 CR0 ; INC LR4 1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ; INC LR5 4 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ; INC LR5 1 ;;
{% for slot in [5,6,8,9] %}
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}SUB{% else %}ADD{% endif %}{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}ADD{% else %}SUB ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ; INC LR5 {{ 2 if slot == 6 else 1 }}{% endif %} ;;
{% endfor %}
    MULT.RC.VE LR11 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.MAX ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.norm }} LR4 ;;
    LD.MULT R0 LR4 {{ cr.norm }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ADD LR5 LR4 {{ cr.M }} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.norm }} LR5 ;;
{% endcall %}

{# Sum the weights and refine the rounded reciprocal. #}
{{ clear() }}
{% call(ds) tiles('sum') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; AGG.SUM LR0 {{ ds }} ;;
{% endcall %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ;;
    ADD LR4 LR2 {{ cr.M }} ; SET LR3 CR0 ;;
    ADD LR4 LR4 {{ cr.M }} ;;
replicate_inverse:
    ACTIVATE.QUANTIZE rsqrt {{ full }} {{ norm_q }} {{ cr.norm }} LR4 ;;
    INC LR4 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.K }} replicate_inverse ;;
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row ;;

{# Pipeline the scalar gather, keeping the next source row one load ahead. #}
{% macro scatter(index,fmt) %}MULT.EE {{ index }} CR1 0 LR0 {{ full }} {{ fmt }} ; ACC.RESHAPE LRD12 LRD12 7{% endmacro %}
{% macro gather(label,index,fmt) %}
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR5 LR6 ;;
    LD.MULT R0 LR4 {{ cr.norm }} ; DEC LR5 1 ; BEQ LR5 CR1 {{ label }}_single ;;
    LD.MULT R0 LR4 {{ cr.norm }} ; {{ scatter(index,fmt) }} ; ADD LR4 LR4 {{ cr.K }} ; DEC LR5 1 ; BEQ LR5 CR1 {{ label }}_last ;;
{{ label }}_next:
    LD.MULT R0 LR4 {{ cr.norm }} ; {{ scatter(index,fmt) }} ; ADD LR4 LR4 {{ cr.K }} ; DEC LR5 1 ; ADDBI LRD12 1 ; BNE LR5 CR1 {{ label }}_next ;;
{{ label }}_last:
    ADDBI LRD12 1 ;;
{{ label }}_single:
    {{ scatter(index,fmt) }} ; ADD LR4 LR4 {{ cr.K }} ;;
{% endmacro %}
{% macro transpose(label,ds) %}
    SET LR1 LR4 ;;
    ADD LR4 LR1 {{ cr.M }} ;;
{{ gather(label ~ '_residual','LR10',work) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    SET LR4 LR1 ;;
{{ gather(label ~ '_high','LR10',work) }}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
{{ imm('LR5',10) }}
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ norm_q }} {{ cr.tmp }} LR0 ;;
    {# The inverse is independent of the column. Gather it into output lanes
       on the first column, then reuse that vector for the entire batch tile.
       Roots are dead here; remaining rows (LR8) uniquely index the tiles. #}
    BNE LR9 CR0 {{ label }}_inverse_ready ;;
    ADD LR4 LR1 {{ cr.M }} ;;
    ADD LR4 LR4 {{ cr.M }} ;;
{{ gather(label ~ '_inverse','LR0',norm_q) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ norm_q }} {{ cr.roots }} LR8 ;;
{{ label }}_inverse_ready:
    LD.MULT.CYCLIC LR8 {{ cr.roots }} LR0 ;;
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
    INC LR3 1 ;;
{% endmacro %}
    SET LR2 CR0 ; SET LR3 CR0 ;;
{{ imm('LR11',128) }}
transpose_batch:
    SET LR10 CR0 ; SET LR9 CR0 ; SET LR7 CR0 ;;
transpose_column:
    ADD LR4 LR2 LR7 ; SET LR8 LR14 ; SET LR6 LR11 ;;
    BLE.S LR8 LR11 transpose_tail ;;
transpose_tile:
{{ transpose('gather_full',full) }}
    DEC LR8 128 ;;
    BLT.S LR11 LR8 transpose_tile ;;
transpose_tail:
    SET LR6 LR8 ;;
{{ transpose('gather_tail',out_tail) }}
    INC LR9 1 ; INC LR10 1 ;;
    BEQ LR9 LR15 transpose_next_batch ;;
    BLT.S LR10 LR11 transpose_column ;;
    SET LR10 CR0 ; INC LR7 1 ; B transpose_column ;;
transpose_next_batch:
    ADD LR2 LR2 {{ cr.row_group }} ;;
    BLT.S LR2 {{ cr.M }} transpose_batch ;;
    HALT ;;
