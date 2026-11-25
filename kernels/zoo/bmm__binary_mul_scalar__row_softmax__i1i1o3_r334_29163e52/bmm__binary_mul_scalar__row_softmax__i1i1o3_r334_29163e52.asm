{% set full = cr.ds_pair ~ '.L' %}
{% set tail = cr.ds_pair ~ '.H' %}
{% set wide = cr.work_qf ~ '.L' %}
{% set fine = cr.work_qf ~ '.H' %}
{% set scalar = cr.astride_pack ~ '.H' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set w = cr.work %}
{% macro imm(r,n) %}
    SET {{ r }} CR0 ;;
    INC {{ r }} {{ n }} ;;
{% endmacro %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ wide }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{# Build split log2(e)/(2 sqrt(K)) coefficients in scratch. #}
{% macro coefficient(p,count,slot,tag) %}
    {{ imm('LR5',slot) }}
    {{ imm('LR6',p) }}
    LD.MULT R0 LR0 {{ w }} ;;
    {{ clear() }}
pow_{{ tag }}_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 pow_{{ tag }}_{{ slot }} ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ wide }} {{ w }} LR5 ;;
    LD.MULT R0 LR5 {{ w }} ;;
    {{ clear() }}
    {{ imm('LR6',count) }}
coef_{{ tag }}_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.ADD ; DEC LR6 1 ;;
    BNE LR6 CR0 coef_{{ tag }}_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} LR5 ;;
{% endmacro %}
    SET LR0 CR0 ;;
    {{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ wide }} {{ w }} LR0 ;;
    {{ imm('LR6',32) }}
    BNE LR6 {{ cr.s0_k }} scale64 ;;
{% for p,c,s in [(3,1,1),(13,21,2),(19,24,3),(25,9,14)] %}
    {{ coefficient(p,c,s,'k32') }}
{% endfor %}
    B start ;;
scale64:
{% for p,c,s in [(4,1,1),(9,15,2),(14,26,3),(21,87,14)] %}
    {{ coefficient(p,c,s,'k64') }}
{% endfor %}
start:
    {{ coefficient(5,1,9,'center') }}
    {{ coefficient(30,1,10,'bias') }}
    {{ coefficient(3,1,11,'initial') }}
    SET LR1 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;

{% macro tiles(tag) %}
    SET LR10 CR0 ;;
    {{ imm('LR5',16) }}
{{ tag }}_next:
    INC LR10 1 ;;
    BEQ LR10 {{ cr.tiles }} {{ tag }}_tail ;;
    {{ caller(full) }}
    B {{ tag }}_next ;;
{{ tag }}_tail:
    {{ caller(tail) }}
{% endmacro %}
{% macro split(reg) %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} {{ reg }} ;;
{% for i in range(2) %}
    LD.MULT R0 {{ reg }} {{ w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.SUB ; INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} {{ reg }} ;;
{% endfor %}
{% endmacro %}

{# Select the query lane directly in the producer layout. #}
head:
    SET LR7 CR0 ; SET LR15 CR0 ; SET LR8 {{ cr.s0_m }} ;;
query:
    SET LR10 CR0 ;;
    {{ imm('LR5',16) }}
dot_tile:
    ADD LR9 LR3 LR10 ; ADD LR11 LR1 LR7 ; SET LR12 {{ cr.s0_k }} ;;
    {{ clear() }}
dot_block:
{% for i in range(16) %}
{% if loop.first %}
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
{% endif %}
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR0 ; ADD LR11 LR11 {{ cr.astride_pack }}.L ;;
    MULT.RC.VE LR0 LR15 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; ADD LR9 LR9 {{ cr.tiles }} ; {% if loop.last %}DEC LR12 16 ; {% else %}LD.MULT R0 LR11 {{ cr.in0 }} ; {% endif %};;
{% endfor %}
    BNE LR12 CR0 dot_block ;;
    {{ split('LR5') }}
    INC LR5 2 ; INC LR10 1 ;;
    BLT.S LR10 {{ cr.tiles }} dot_tile ;;

{% macro maximum(tag,offset) %}
    {{ clear() }}
    {{ imm('LR5',offset) }}
    LD.MULT R0 LR5 {{ w }} ;;
    BEQ {{ cr.tiles }} CR1 {{ tag }}_single ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; AGG.MAX.FIRST LR0 {{ full }} ;;
    SET LR10 CR1 ;;
{{ tag }}_next:
    INC LR5 4 ; INC LR10 1 ;;
    LD.MULT R0 LR5 {{ w }} ;;
    BEQ LR10 {{ cr.tiles }} {{ tag }}_tail ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; AGG.MAX LR0 {{ full }} ;;
    B {{ tag }}_next ;;
{{ tag }}_tail:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ wide }} ; AGG.MAX LR0 {{ tail }} ;;
    B {{ tag }}_ready ;;
{{ tag }}_single:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ wide }} ; AGG.MAX.FIRST LR0 {{ tail }} ;;
{{ tag }}_ready:
    {{ imm('LR6',4) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} LR6 ;;
    LD.MULT R0 LR6 {{ w }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} LR6 ;;
{% endmacro %}
    {{ maximum('maxhigh',16) }}
    {# Start below the maximum even if its high part rounded up. #}
    LD.MULT.CYCLIC LR6 {{ w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.SUB.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.MAX ;;
    {{ imm('LR11',11) }}
    INC LR11 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} LR11 ;;
    LD.MULT R0 LR11 {{ w }} ;;
    {{ imm('LR2',128) }}
    DEC LR11 1 ; LD.MULT.CYCLIC LR11 {{ w }} LR2 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR2 LR0 0 LR0 {{ full }} {{ wide }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} LR6 ;;
    {{ imm('LR13',3) }}
center_pass:
    SET LR10 CR0 ;;
    {{ imm('LR5',16) }}
center_tile:
    LD.MULT R0 LR5 {{ w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.ADD.FIRST ; LD.MULT R0 LR6 {{ w }} ; INC LR5 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.SUB ; LD.MULT R0 LR5 {{ w }} ;;
{% for i in range(2) %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.ADD ; INC LR5 1 ; {% if loop.last %}ACTIVATE.QUANTIZE relu {{ full }} {{ wide }} {{ w }} LR5 ; {% else %}LD.MULT R0 LR5 {{ w }} ; {% endif %};;
{% endfor %}
    DEC LR5 3 ;;
    {{ split('LR5') }}
    INC LR5 2 ; INC LR10 1 ;;
    BLT.S LR10 {{ cr.tiles }} center_tile ;;
    {{ maximum('maxpositive',19) }}
    DEC LR13 1 ;;
    BEQ LR13 CR0 roots ;;
    LD.MULT.CYCLIC LR6 {{ w }} LR0 ;;
    {{ imm('LR11',9) }}
    LD.MULT R0 LR11 {{ w }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ wide }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} LR6 ;;
    B center_pass ;;

roots:
{% call(ds) tiles('root') %}
    LD.MULT.CYCLIC LR5 {{ w }} LR0 ;;
    INC LR5 1 ;;
    {{ imm('LR11',128) }}
    LD.MULT.CYCLIC LR5 {{ w }} LR11 ;;
    SET LR2 LR11 ;;
    INC LR2 128 ;
    LD.MULT.CYCLIC LR6 {{ w }} LR2 ;;
    SET LR13 LR2 ;;
    INC LR13 128 ; INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{ w }} LR13 ;;
    SET LR12 CR1 ;;
    {{ clear() }}
{% for i in range(4) %}
{% if loop.last %}
    {{ imm('LR12',14) }}
{% endif %}
    LD.MULT R0 LR12 {{ w }} ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ ds }} {{ wide }} ; ACC.{{ 'ADD' if i >= 2 else 'SUB' }} ; INC LR12 1 ;;
    MULT.RC.VE LR2 LR0 0 LR0 {{ ds }} {{ wide }} ; ACC.{{ 'SUB' if i >= 2 else 'ADD' }} ;;
    MULT.RC.VE LR11 LR0 0 LR0 {{ ds }} {{ wide }} ; ACC.{{ 'ADD' if i >= 2 else 'SUB' }} ;;
    MULT.RC.VE LR13 LR0 0 LR0 {{ ds }} {{ wide }} ; ACC.{{ 'ADD' if i >= 2 else 'SUB' }} ;;
{% endfor %}
    {{ imm('LR11',7) }}
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ fine }} ; ACC.MAX ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ wide }} {{ w }} LR11 ;;
    LD.MULT R0 LR11 {{ w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ wide }} ; ACC.SUB ;;
    INC LR11 1 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ wide }} {{ w }} LR11 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ wide }} ; ACC.SUB.FIRST ;;
    LD.MULT R0 LR11 {{ w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ wide }} ; ACC.SUB ;;
    {{ imm('LR11',10) }}
    LD.MULT R0 LR11 {{ w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ wide }} ; ACC.SUB ; DEC LR5 2 ;;
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ fine }} {{ w }} LR5 ;;
    INC LR5 4 ;;
{% endcall %}
    {{ clear() }}
{% call(ds) tiles('sum') %}
    LD.MULT R0 LR5 {{ w }} ;;
    LD.MULT.CYCLIC LR5 {{ w }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ fine }} ; AGG.SUM LR0 {{ ds }} ; INC LR5 4 ;;
{% endcall %}
    {{ imm('LR6',5) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ scalar }} {{ w }} LR6 ;;
    LD.MULT R0 LR6 {{ w }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ scalar }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE rsqrt {{ full }} {{ fine }} {{ w }} LR6 ;;
    {{ imm('LR13',12) }}
{% call(ds) tiles('output') %}
    LD.MULT.CYCLIC LR5 {{ w }} LR0 ;;
    LD.MULT R0 LR6 {{ w }} ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ ds }} {{ fine }} ; ACC.ADD.FIRST ; INC LR5 4 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ wide }} {{ w }} LR13 ;;
    LD.MULT R0 LR13 {{ w }} ;;
    {{ imm('LR2',128) }}
    LD.MULT.CYCLIC LR13 {{ w }} LR2 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ wide }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ wide }} {{ w }} LR13 ;;
    LD.MULT.CYCLIC LR13 {{ w }} LR0 ;;
    MULT.RC.VV LR2 R0 0 LR0 {{ ds }} {{ wide }} ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ wide }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ wide }} ; ACC.ADD ; LD.MULT R1 LR13 {{ w }} ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ wide }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endcall %}
    DEC LR8 1 ;;
    BEQ LR8 CR0 next_head ;;
    INC.MODP2 LR15 CR1 7 ;;
    BNE LR15 CR0 query ;;
    INC LR7 1 ; B query ;;
next_head:
    ADD LR1 LR1 {{ cr.ahead }} ; SET LR3 LR9 ; DEC LR14 1 ;;
    SUB LR3 LR3 {{ cr.tiles }} ;;
    INC LR3 1 ;;
    BNE LR14 CR0 head ;;
    HALT ;;
