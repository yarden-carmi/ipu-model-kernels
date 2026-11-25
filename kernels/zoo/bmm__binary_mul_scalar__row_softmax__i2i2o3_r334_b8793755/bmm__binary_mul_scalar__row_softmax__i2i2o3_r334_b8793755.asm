{% set full = cr.ds_pair ~ '.L' %}
{% set tail = cr.ds_pair ~ '.H' %}
{% set dot = cr.dot_ds ~ '.L' %}
{% set wide = cr.work_qf ~ '.L' %}
{% set fine = cr.work_qf ~ '.H' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set w = cr.work %}
{% macro imm(r,n) %}
    SET {{ r }} CR0 ;;
    INC {{ r }} {{ n }} ;;
{% endmacro %}
{% macro clear(ds) %}
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ wide }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro coefficient(p,c,s,tag) %}
    {{ imm('LR5',s) }}
    {{ imm('LR6',p) }}
    LD.MULT R0 LR0 {{ w }} ;;
    {{ clear(full) }}
power_{{ tag }}_{{ s }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ tag }}_{{ s }} ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ wide }} {{ w }} LR5 ;;
    LD.MULT R0 LR5 {{ w }} ;;
    {{ clear(full) }}
    {{ imm('LR6',c) }}
coef_{{ tag }}_{{ s }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.ADD ; DEC LR6 1 ;;
    BNE LR6 CR0 coef_{{ tag }}_{{ s }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} LR5 ;;
{% endmacro %}
{% macro split() %}
{# Keep the leading value and two quantization residuals in each tile. #}
{% for i in range(3) %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} LR5 ;;
{% if not loop.last %}
    LD.MULT R0 LR5 {{ w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.SUB ;;
{% endif %}
    INC LR5 1 ;;
{% endfor %}
    INC LR5 1 ;;
{% endmacro %}
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
{% macro maximum(tag,offset) %}
    {{ clear(full) }}
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

    SET LR0 CR0 ;;
    {{ clear(full) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ wide }} {{ w }} LR0 ;;
    {{ imm('LR6',32) }}
    BNE LR13 LR6 scale64 ;;
{% for p,c,s in [(3,1,1),(13,21,2),(19,24,3),(25,9,14)] %}
    {{ coefficient(p,c,s,'k32') }}
{% endfor %}
    B start ;;
scale64:
{% for p,c,s in [(4,1,1),(9,15,2),(14,26,3),(21,87,14)] %}
    {{ coefficient(p,c,s,'k64') }}
{% endfor %}
start:
    {{ coefficient(30,1,10,'bias') }}
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
    {{ imm('LR15',128) }}

{# LR1/LR2 are the head's row/lane offsets within both stored inputs. #}
head:
    SET LR7 LR1 ; SET LR8 {{ cr.s0_m }} ;;
query:
    {# Align the query head once; key heads are selected by the cyclic offset. #}
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR2 CR1 0 LR0 {{ dot }} {{ qi }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ dot }} {{ qi }} {{ w }} LR0 ;;
    SET LR9 LR1 ; SET LR10 CR0 ;;
    {{ imm('LR5',16) }}
dot_tile:
    {{ clear(full) }}
    LD.MULT R1 LR0 {{ w }} ; SET LR11 CR0 ;;
dot_column:
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR0 ;;
    MULT.RC.VV LR2 R1 0 LR0 {{ dot }} {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR11 {{ dot }} ; INC LR10 1 ; ADD LR9 LR9 {{ cr.bstride }} ;;
    INC LR11 1 ;;
    BEQ LR10 LR12 dot_last ;;
    BNE LR11 LR15 dot_column ;;
    {{ split() }}
    B dot_tile ;;
dot_last:
    {{ split() }}

    {{ maximum('maxhigh',16) }}
    {# Refine the row shift using the maximum of the split residual logits. #}
    {{ imm('LR3',7) }}
center_pass:
    SET LR10 CR0 ;;
    {{ imm('LR5',16) }}
center_tile:
    LD.MULT R0 LR5 {{ w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.ADD.FIRST ; INC LR5 1 ;;
    LD.MULT R0 LR6 {{ w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.SUB ;;
{% for i in range(2) %}
    LD.MULT R0 LR5 {{ w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.ADD ; INC LR5 1 ;;
{% endfor %}
    DEC LR5 3 ;;
    {{ split() }}
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.tiles }} center_tile ;;
    {{ maximum('maxresidual',16) }}
    DEC LR3 1 ;;
    BEQ LR3 CR0 roots ;;
    B center_pass ;;

roots:
{# Apply half the base-2 exponent; square the resulting roots for normalization. #}
{% call(ds) tiles('root') %}
    LD.MULT.CYCLIC LR5 {{ w }} LR0 ;;
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ w }} LR15 ;;
    INC LR5 1 ;;
    ADD LR11 LR15 LR15 ;;
    LD.MULT.CYCLIC LR6 {{ w }} LR11 ;;
    ADD LR3 LR11 LR15 ;;
    LD.MULT.CYCLIC LR5 {{ w }} LR3 ;;
    SET LR9 CR1 ;;
    {{ clear(ds) }}
{% for i in range(4) %}
{% if loop.last %}
    {{ imm('LR9',14) }}
{% endif %}
    LD.MULT R0 LR9 {{ w }} ;;
{% for r in ['LR0','LR15','LR3','LR11'] %}
    MULT.RC.VE {{ r }} LR0 0 LR0 {{ ds }} {{ wide }} ; ACC.{{ 'ADD' if (i >= 2) != loop.last else 'SUB' }}{% if loop.first %} ; INC LR9 1{% endif %} ;;
{% endfor %}
{% endfor %}
    {{ imm('LR11',7) }}
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ fine }} ; ACC.MAX ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ wide }} {{ w }} LR11 ;;
    LD.MULT R0 LR11 {{ w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ wide }} ; ACC.SUB ; INC LR11 1 ;;
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

    {{ clear(full) }}
{% call(ds) tiles('sum') %}
    LD.MULT R0 LR5 {{ w }} ;;
    LD.MULT.CYCLIC LR5 {{ w }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ fine }} ; AGG.SUM LR0 {{ ds }} ; INC LR5 4 ;;
{% endcall %}
    {{ imm('LR6',5) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ fine }} {{ w }} LR6 ;;
    LD.MULT R0 LR6 {{ w }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ fine }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE rsqrt {{ full }} {{ fine }} {{ w }} LR6 ;;
    {{ imm('LR3',12) }}
{% call(ds) tiles('output') %}
    LD.MULT.CYCLIC LR5 {{ w }} LR0 ;;
    LD.MULT R0 LR6 {{ w }} ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ ds }} {{ fine }} ; ACC.ADD.FIRST ; INC LR5 4 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ wide }} {{ w }} LR3 ;;
    LD.MULT R0 LR3 {{ w }} ;;
    LD.MULT.CYCLIC LR3 {{ w }} LR15 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ wide }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ wide }} {{ w }} LR3 ;;
    LD.MULT.CYCLIC LR3 {{ w }} LR0 ;;
    MULT.RC.VV LR15 R0 0 LR0 {{ ds }} {{ wide }} ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ wide }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ wide }} ; ACC.ADD ; LD.MULT R1 LR3 {{ w }} ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ wide }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endcall %}
    {{ imm('LR15',128) }}
    ADD LR7 LR7 {{ cr.astride }} ; DEC LR8 1 ;;
    BNE LR8 CR0 query ;;
    DEC LR14 1 ;;
    BEQ LR14 CR0 done ;;
    ADD LR2 LR2 LR13 ;;
    BLT.S LR2 LR15 head ;;
    SUB LR2 LR2 LR15 ; INC LR1 1 ; B head ;;
done:
    HALT ;;
