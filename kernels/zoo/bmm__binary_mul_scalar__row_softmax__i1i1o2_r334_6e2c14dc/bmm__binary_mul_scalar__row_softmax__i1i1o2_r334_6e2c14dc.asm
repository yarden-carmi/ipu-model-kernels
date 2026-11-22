{% set full = cr.ds_pair ~ '.L' %}
{% set logq = cr.scratch_qf ~ '.L' %}
{% set expq = cr.scratch_qf ~ '.H' %}
{% set centerq = cr.center_qf ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro slot(reg, index) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ index }} ;;
{% endmacro %}
{% macro clear(ds, q) %}
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{# Synthesize dyadic components of log2(e)/sqrt(32). #}
{% macro coefficient(p, count, index) %}
{{ slot('LR5', index) }}
{{ slot('LR6', p) }}
{{ clear(full, logq) }}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
power_{{ index }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ logq }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ index }} ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ logq }} {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
{{ clear(full, logq) }}
{{ slot('LR6', count) }}
mantissa_{{ index }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ logq }} ; ACC.ADD ; DEC LR6 1 ;;
    BNE LR6 CR0 mantissa_{{ index }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ logq }} {{ cr.tmp }} LR5 ;;
{% endmacro %}
    SET LR0 CR0 ;;
{{ clear(full, logq) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ logq }} {{ cr.tmp }} LR0 ;;
{% for p,count,index in [(3,1,1),(13,21,2),(19,24,3),(1,8,7)] %}
{{ coefficient(p,count,index) }}
{% endfor %}
{{ slot('LR11',128) }}
    ADD LR12 LR11 LR11 ;;
    ADD LR13 LR12 LR11 ;;
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ;;

{% macro product(ds, first) %}
    LD.MULT R0 LR6 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD{% if first %}.FIRST{% endif %} ; ADD LR5 LR5 {{ cr.strides }}.L ; ADD LR6 LR6 {{ cr.strides }}.H ; DEC LR7 1 ;;
{% endmacro %}

{% macro tile(tag, ds, last) %}
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR10 CR0 ;;
{{ tag }}_column:
    ADD LR5 LR1 LR4 ; ADD LR6 LR2 LR9 ; SET LR7 {{ cr.s0_k }} ;;
    {{ product(ds, true) }}
    BEQ LR7 CR0 {{ tag }}_dot_done ;;
{{ tag }}_dot:
    {{ product(ds, false) }}
    BNE LR7 CR0 {{ tag }}_dot ;;
{{ tag }}_dot_done:
    ACTIVATE.QUANTIZE identity {{ ds }} {{ logq }} {{ cr.logits }} LR10 ;;
    LD.MULT R0 LR10 {{ cr.logits }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ logq }} ; ACC.SUB ; INC LR10 1 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ logq }} {{ cr.logits }} LR10 ;;
    INC LR10 1 ; DEC LR15 1 ;;
    BEQ LR15 CR0 {{ tag }}_dots_done ;;
    INC.MODP2 LR8 CR1 7 ;;
    BNE LR8 CR0 {{ tag }}_column ;;
    INC LR9 1 ; B {{ tag }}_column ;;
{{ tag }}_dots_done:
{% if last %}
    SUB LR1 LR5 LR4 ; SUB LR2 LR6 LR9 ;;
{% endif %}
    {# Restore the column count while reducing high parts to a lane-wise maximum. #}
    SET LR5 CR0 ;;
{% macro maxpart(ds, first) %}
    LD.MULT R0 LR5 {{ cr.logits }} ;; 
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ logq }} ; ACC.MAX{% if first %}.FIRST{% endif %} ; INC LR5 1 ; INC LR15 1 ;;
    INC LR5 1 ;;
{% endmacro %}
    {{ maxpart(ds, true) }}
    BEQ LR5 LR10 {{ tag }}_max_done ;;
{{ tag }}_max:
    {{ maxpart(ds, false) }}
    BLT.S LR5 LR10 {{ tag }}_max ;;
{{ tag }}_max_done:
{{ slot('LR5',4) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ logq }} {{ cr.tmp }} LR5 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR13 ;;
    SET LR5 CR0 ; SET LR6 CR0 ;;
{{ tag }}_center:
    LD.MULT R0 LR5 {{ cr.logits }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ logq }} ; ACC.ADD.FIRST ; INC LR5 1 ;;
    MULT.RC.VE LR13 CR1 0 LR0 {{ ds }} {{ logq }} ; ACC.SUB ;;
    LD.MULT R0 LR5 {{ cr.logits }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ logq }} ; ACC.ADD ; INC LR5 1 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ centerq }} {{ cr.exps }} LR6 ;;
    INC LR6 1 ; BLT.S LR5 LR10 {{ tag }}_center ;;
    SET LR5 CR0 ;;
{% macro centermax(ds, first) %}
    LD.MULT R0 LR5 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ centerq }} ; ACC.MAX{% if first %}.FIRST{% endif %} ; INC LR5 1 ;;
{% endmacro %}
    {{ centermax(ds, true) }}
    BEQ LR5 LR15 {{ tag }}_center_done ;;
{{ tag }}_center_max:
    {{ centermax(ds, false) }}
    BLT.S LR5 LR15 {{ tag }}_center_max ;;
{{ tag }}_center_done:
{{ slot('LR5',6) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ logq }} {{ cr.tmp }} LR5 ;;
    SET LR5 CR0 ; SET LR6 CR0 ;;
{{ tag }}_exp:
    LD.MULT.CYCLIC LR5 {{ cr.logits }} LR11 ;;
    INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.logits }} LR12 ;;
{{ slot('LR7',6) }}
    LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
{{ slot('LR7',7) }}
    LD.MULT R0 LR7 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ logq }} ; ACC.SUB.FIRST ; SET LR7 CR0 ;;
{% for index in range(1,4) %}
    INC LR7 1 ;;
    LD.MULT R0 LR7 {{ cr.tmp }} ;;
    MULT.RC.VE LR11 LR0 0 LR0 {{ ds }} {{ logq }} ; ACC.{{ 'SUB' if loop.last else 'ADD' }} ;;
    MULT.RC.VE LR12 LR0 0 LR0 {{ ds }} {{ logq }} ; ACC.{{ 'SUB' if loop.last else 'ADD' }} ;;
    MULT.RC.VE LR13 LR0 0 LR0 {{ ds }} {{ logq }} ; ACC.{{ 'ADD' if loop.last else 'SUB' }} ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ ds }} {{ logq }} ; ACC.{{ 'ADD' if loop.last else 'SUB' }} ;;
{% endfor %}
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ expq }} {{ cr.exps }} LR6 ;;
    INC LR5 1 ; INC LR6 1 ;;
    BLT.S LR6 LR15 {{ tag }}_exp ;;
    SET LR5 CR0 ;;
{{ clear(ds, expq) }}
{{ tag }}_sum:
     LD.MULT.CYCLIC LR5 {{ cr.exps }} LR0 ;;
     MULT.RC.VS LR0 0 LR0 {{ ds }} {{ expq }} ; ACC.ADD ; INC LR5 1 ;;
    BLT.S LR5 LR15 {{ tag }}_sum ;;
{{ slot('LR7',5) }}
     ACTIVATE.QUANTIZE rsqrt {{ ds }} {{ expq }} {{ cr.tmp }} LR7 ;;
    LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR11 ;;
    ADD LR6 LR3 LR4 ; SET LR5 CR0 ;;
{{ tag }}_out:
    LD.MULT R0 LR5 {{ cr.exps }} ;;
     MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ expq }} ; ACC.ADD.FIRST ;;
     ACTIVATE.QUANTIZE identity {{ ds }} {{ expq }} {{ cr.tmp }} LR7 ;;
     LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
     MULT.RC.VS LR0 0 LR0 {{ ds }} {{ expq }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    ADD LR6 LR6 {{ cr.strides }}.L ; INC LR5 1 ;;
    BLT.S LR5 LR15 {{ tag }}_out ;;
{% endmacro %}

next_tile:
    ADD LR7 LR4 CR1 ;;
    BEQ LR7 {{ cr.strides }}.L tail ;;
{{ tile('full', full, false) }}
    INC LR4 1 ; B next_tile ;;
tail:
{{ tile('tail', cr.ds_pair ~ '.H', true) }}
    SUB LR3 LR6 LR4 ; SET LR4 CR0 ; DEC LR14 1 ;;
    BNE LR14 CR0 next_tile ;;
    HALT ;;
