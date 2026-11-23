{% set full = cr.ds_pair ~ '.L' %}
{% set tail = cr.ds_pair ~ '.H' %}
{% set wide = cr.work_qf ~ '.L' %}
{% set fine = cr.work_qf ~ '.H' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set w = cr.work %}
{% macro imm(reg, value) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ value }} ;;
{% endmacro %}
{% macro clear(ds) %}
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ wide }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro coefficient(p, count, slot, tag) %}
    {{ imm('LR5', slot) }}
    {{ imm('LR6', p) }}
    LD.MULT R0 LR0 {{ w }} ;;
    {{ clear(full) }}
pow_{{ tag }}_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 pow_{{ tag }}_{{ slot }} ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ wide }} {{ w }} LR5 ;;
    LD.MULT R0 LR5 {{ w }} ;;
    {{ clear(full) }}
    {{ imm('LR6', count) }}
coef_{{ tag }}_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.ADD ; DEC LR6 1 ;;
    BNE LR6 CR0 coef_{{ tag }}_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} LR5 ;;
{% endmacro %}
{# LR1: head A row; LR2: head A lane; LR3: head B row; LR4: output row.
   LR7 and LR8 track the current query and remaining queries. #}
    SET LR0 CR0 ;;
    {{ clear(full) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ wide }} {{ w }} LR0 ;;
    {{ imm('LR6',32) }}
    BNE LR6 {{ cr.s0_k }} scale64 ;;
{% for p,c,s in [(3,1,1),(13,21,2),(19,24,3),(25,9,14)] %}
    {{ coefficient(p,c,s,'k32') }}
{% endfor %}
    B start ;;
scale64:
{% for p,c,s in [(4,1,1),(9,15,2),(14,27,3)] %}
    {{ coefficient(p,c,s,'k64') }}
{% endfor %}
    {{ imm('LR5',14) }}
    {{ clear(full) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} LR5 ;;
start:
    {{ coefficient(5,1,9,'centering') }}
    {{ coefficient(30,1,10,'bias') }}
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ;;

{# One common runtime full-tile loop and one masked tail per pass. #}
{% macro tiles(tag) %}
    SET LR10 CR0 ;;
    {{ imm('LR5',16) }}
{{ tag }}_next:
    ADD LR10 LR10 CR1 ;;
    BEQ LR10 {{ cr.tiles }} {{ tag }}_tail ;;
    {{ caller(full,tag ~ '_full') }}
    B {{ tag }}_next ;;
{{ tag }}_tail:
    {{ caller(tail,tag ~ '_last') }}
{% endmacro %}

head:
    SET LR7 LR1 ; SET LR8 {{ cr.s0_m }} ;;
query:
    SET LR10 CR0 ;;
    {{ imm('LR5',16) }}
dot_tile:
    ADD LR9 LR3 LR10 ; SET LR11 LR7 ; SET LR12 {{ cr.blocks }} ;;
    SET LR15 LR2 ;;
    {{ clear(full) }}
dot_block:
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR0 ;;
{% for i in range(16) %}
    MULT.RC.VE LR0 LR15 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; ADD LR9 LR9 {{ cr.tiles }} ; {% if not loop.last %}LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR0 ; {% endif %}{% if not loop.first %}INC.MODP2 LR15 CR1 7 ; {% endif %};;
{% endfor %}
    DEC LR12 1 ; INC.MODP2 LR15 CR1 7 ;;
    BEQ LR12 CR0 dot_save ;;
    BNE LR15 CR0 dot_block ;;
    INC LR11 1 ; B dot_block ;;
dot_save:
{% for i in range(3) %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} LR5 ;;
{% if not loop.last %}
    LD.MULT R0 LR5 {{ w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.SUB ;;
{% endif %}
    INC LR5 1 ;;
{% endfor %}
    INC LR5 1 ; INC LR10 1 ;;
    BLT.S LR10 {{ cr.tiles }} dot_tile ;;

{% macro maximum(tag, offset, slot, q) %}
    {{ clear(full) }}
    {{ imm('LR5',offset) }}
    LD.MULT R0 LR5 {{ w }} ;;
    BEQ {{ cr.tiles }} CR1 {{ tag }}_single ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ;;
    SET LR10 CR1 ;;
{{ tag }}_next:
    INC LR5 4 ; INC LR10 1 ;;
    LD.MULT R0 LR5 {{ w }} ;;
    BEQ LR10 {{ cr.tiles }} {{ tag }}_tail ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ;;
    B {{ tag }}_next ;;
{{ tag }}_tail:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX LR0 {{ tail }} ;;
    B {{ tag }}_ready ;;
{{ tag }}_single:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ;;
{{ tag }}_ready:
    {{ imm('LR6',slot) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ w }} LR6 ;;
    LD.MULT R0 LR6 {{ w }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ w }} LR6 ;;
{% endmacro %}
{{ maximum('maxhigh',16,4,wide) }}

    {{ imm('LR13',4) }}
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
    ACTIVATE.QUANTIZE relu {{ full }} {{ wide }} {{ w }} LR5 ; INC LR5 3 ;;
    DEC LR5 3 ;;
{% for i in range(3) %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ wide }} {{ w }} LR5 ;;
{% if not loop.last %}
    LD.MULT R0 LR5 {{ w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ wide }} ; ACC.SUB ;;
{% endif %}
    INC LR5 1 ;;
{% endfor %}
    INC LR5 1 ; INC LR10 1 ;;
    BLT.S LR10 {{ cr.tiles }} center_tile ;;
{{ maximum('maxpositive',19,4,wide) }}
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
{% call(ds,tag) tiles('root') %}
    LD.MULT.CYCLIC LR5 {{ w }} LR0 ;;
    INC LR5 1 ;;
    {{ imm('LR11',128) }}
    LD.MULT.CYCLIC LR5 {{ w }} LR11 ;;
    SET LR15 LR11 ;;
    INC LR15 128 ;;
    LD.MULT.CYCLIC LR6 {{ w }} LR15 ;;
    SET LR13 LR15 ;;
    INC LR13 128 ; INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{ w }} LR13 ;;
    SET LR12 CR1 ;;
    {{ clear(ds) }}
{% for i in range(4) %}
{% if loop.last %}
    {{ imm('LR12',14) }}
{% endif %}
    LD.MULT R0 LR12 {{ w }} ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ ds }} {{ wide }} ; ACC.{{ 'ADD' if i >= 2 else 'SUB' }} ; INC LR12 1 ;;
    MULT.RC.VE LR11 LR0 0 LR0 {{ ds }} {{ wide }} ; ACC.{{ 'ADD' if i >= 2 else 'SUB' }} ;;
    MULT.RC.VE LR13 LR0 0 LR0 {{ ds }} {{ wide }} ; ACC.{{ 'ADD' if i >= 2 else 'SUB' }} ;;
    MULT.RC.VE LR15 LR0 0 LR0 {{ ds }} {{ wide }} ; ACC.{{ 'SUB' if i >= 2 else 'ADD' }} ;;
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

    {{ clear(full) }}
{% call(ds,tag) tiles('sum') %}
    LD.MULT R0 LR5 {{ w }} ;;
    LD.MULT.CYCLIC LR5 {{ w }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ fine }} ; AGG.SUM LR0 {{ ds }} ; INC LR5 4 ;;
{% endcall %}
    {{ imm('LR6',5) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ fine }} {{ w }} LR6 ;;
    LD.MULT R0 LR6 {{ w }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ fine }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE rsqrt {{ full }} {{ fine }} {{ w }} LR6 ;;
    {{ imm('LR13',12) }}
{% call(ds,tag) tiles('output') %}
    LD.MULT.CYCLIC LR5 {{ w }} LR0 ;;
    LD.MULT R0 LR6 {{ w }} ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ ds }} {{ fine }} ; ACC.ADD.FIRST ; INC LR5 4 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ fine }} {{ w }} LR13 ;;
    LD.MULT R0 LR13 {{ w }} ;;
    LD.MULT.CYCLIC LR13 {{ w }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ fine }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endcall %}
    ADD LR7 LR7 {{ cr.astride }} ; DEC LR8 1 ;;
    BNE LR8 CR0 query ;;
    DEC LR14 1 ;;
    BEQ LR14 CR0 done ;;
    SET LR3 LR9 ; ADD LR2 LR2 {{ cr.s0_k }} ;;
    SUB LR3 LR3 {{ cr.tiles }} ;;
    INC LR3 1 ;;
    {{ imm('LR11',128) }}
    BLT.S LR2 LR11 head ;;
    SUB LR2 LR2 LR11 ; INC LR1 1 ;;
    B head ;;
done:
    HALT ;;
