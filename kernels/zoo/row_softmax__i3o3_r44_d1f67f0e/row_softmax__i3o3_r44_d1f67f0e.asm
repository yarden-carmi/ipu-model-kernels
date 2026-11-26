{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set act = 'relu' if act_out0 | default('identity') == 'identity' else act_out0 %}
{% macro power(delta,slot) %}
{% for i in range(delta) %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} {{ slot }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro coefficient(base,unit,count) %}
    LD.MULT R0 {{ base }} {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 {{ unit }} {{ cr.tmp }} ;;
{% for i in range(count) %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.last %} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} {{ unit }}{% endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR6 CR0 ; SET LR14 CR0 ;;
    INC LR6 5 ; INC LR14 6 ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ; SET LR7 CR1 ; SET LR5 CR0 ;;
{{ power(1,'LR7') }}
{{ power(4,'LR6') }}
{{ power(4,'LR5') }}
{{ power(4,'LR14') }}
{{ coefficient('LR7','LR6',7) }}
{{ coefficient('LR5','LR14',5) }}
    SET LR13 CR0 ;;
    LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR13 ; INC LR13 128 ;;
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ; SET LR4 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR10 LR13 ;;
    INC LR10 128 ; DEC LR4 1 ; SET LR15 {{ cr.rows }} ;;
    DEC LR15 1 ;;
row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; SET LR11 CR0 ; SET LR5 {{ cr.n }} ;;
    BEQ LR3 CR0 gather ;;
    SET LR11 {{ cr.n }} ;;
gather:
    MULT.EE LR11 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD6 LRD8 7 ; INC LR11 1 ; ADDBI LRD8 1 ; DEC LR5 1 ; BNE LR5 CR0 gather ;;
    SET LR11 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    BEQ LR3 CR0 fix_first ;;
    SET LR11 {{ cr.n }} ;;
fix_first:
    MULT.EE LR11 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD6 LRD8 7 ;;
    ACTIVATE.QUANTIZE identity {{ tail }} {{ q }} {{ cr.tiles }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tiles }} ; SET LR1 CR1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ; ACTIVATE.QUANTIZE identity {{ cr.single }}.H {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{% for coeff in ['LR0', 'LR13'] %}
    MULT.RC.VV {{ coeff }} R0 0 LR0 {{ tail }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE {{ coeff }} LR13 0 LR0 {{ tail }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ tail }} {{ root }} {{ cr.roots }} LR0{% endif %} ;;
{% endfor %}
    LD.MULT.CYCLIC LR0 {{ cr.roots }} LR10 ;;
    MULT.RC.VS LR10 0 LR0 {{ tail }} {{ root }} ; AGG.SUM.FIRST LR0 {{ tail }} ; ACTIVATE.QUANTIZE rsqrt {{ cr.single }}.H {{ root }} {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
    MULT.RC.VE LR10 LR13 0 LR0 {{ tail }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ tail }} {{ root }} {{ cr.exps }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.exps }} LR10 ;;
    MULT.RC.VS LR10 0 LR0 {{ tail }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act }} {{ tail }} {{ qo }} {{ cr.out0 }} LR4 ; INC LR4 1 ;;
    BEQ LR4 LR15 done ;;
    BEQ LR3 CR0 second ;;
    SET LR3 CR0 ; INC LR2 1 ; B row ;;
second:
    SET LR3 CR1 ; B row ;;
done:
    HALT ;;
