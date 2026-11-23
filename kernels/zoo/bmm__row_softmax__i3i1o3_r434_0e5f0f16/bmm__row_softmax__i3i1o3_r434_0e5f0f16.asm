{% set full = cr.width ~ '.L' %}
{% set tail = cr.width ~ '.H' %}
{% set sq = cr.workq ~ '.L' %}
{% set eq = cr.workq ~ '.H' %}
{% set single = cr.one ~ '.H' %}
{% macro addr(reg, n) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ n }} ;;
{% endmacro %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ sq }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro coefficient(slot, power, count, cyclic) %}
    LD.MULT R0 LR0 {{ cr.temp }} ;;
    {{ addr('LR6', power) }}
    {{ addr('LR7', slot) }}
    {{ clear() }}
coef_pow_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.SUB ; DEC LR6 1 ; BNE LR6 CR1 coef_pow_{{ slot }} ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ sq }} {{ cr.temp }} LR7 ;;
    LD.MULT R0 LR7 {{ cr.temp }} ; INC LR6 {{ count }} ;;
    {{ clear() }}
coef_sum_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.ADD ; DEC LR6 1 ; BNE LR6 CR1 coef_sum_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ sq }} {{ cr.temp }} LR7 ;;
    LD.MULT.CYCLIC LR7 {{ cr.temp }} {{ cyclic }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    SET LR8 CR0 ;;
    {{ addr('LR1',128) }}
    SET LR2 LR1 ;;
    INC LR2 128 ;;
    LD.MULT R0 LR0 {{ cr.in0 }} ;;
    {{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ sq }} {{ cr.temp }} LR0 ;;
    SET LR9 LR2 ;;
    INC LR9 128 ;;
    {{ coefficient(1,5,23,'LR1') }}
    {{ coefficient(2,13,21,'LR2') }}
    {{ coefficient(3,20,36,'LR9') }}
    {{ coefficient(4,3,1,'LR0') }}
    {{ coefficient(6,5,1,'LR0') }}
    {{ coefficient(7,1,255,'LR0') }}
    LD.MULT R0 LR7 {{ cr.temp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.SUB.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ sq }} {{ cr.temp }} LR7 ;;
    {{ coefficient(10,16,1,'LR0') }}
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ eq }} {{ cr.temp }} LR7 ;;
    {{ coefficient(11,32,1,'LR0') }}

row:
    SET LR6 CR0 ; LD.MULT R0 LR3 {{ cr.in0 }} ;;
tile:
    ADD LR7 LR5 LR6 ; SET LR9 CR0 ;;
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ;;
{% macro product(first) %}
    MULT.RC.VE LR0 LR9 0 LR0 {{ full }} {{ cr.qf_in1 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; {{ 'BEQ' if first else 'BLT.S' }} LR9 {{ cr.klast }} {{ 'score_store' if first else 'kloop' }} ;;
{% endmacro %}
    {{ product(true) }}
kloop:
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ; ADD LR7 LR7 {{ cr.chunks }} ; INC LR9 1 ;;
    {{ product(false) }}
score_store:
    BEQ LR6 LR13 score_tail ;;
{% macro split_score(ds) %}
    SET LR9 LR6 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ sq }} {{ cr.score }} LR6 ;;
{% for i in range(2) %}
    LD.MULT R1 LR9 {{ cr.score }} ;;
    MULT.VE LR1 CR1 0 LR0 {{ ds }} {{ sq }} ; ACC.SUB ; ADD LR9 LR9 {{ cr.chunks }} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ sq }} {{ cr.score }} LR9 ;;
{% endfor %}
{% endmacro %}
    {{ split_score(full) }}
    INC LR6 1 ; B tile ;;
score_tail:
    {{ split_score(tail) }}
    LD.MULT R0 LR0 {{ cr.score }} ; SET LR6 CR0 ;;
    BEQ LR13 CR0 max_single ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ sq }} ; AGG.MAX.FIRST LR0 {{ full }} ; INC LR6 1 ;;
max_loop:
    LD.MULT R0 LR6 {{ cr.score }} ; BEQ LR6 LR13 max_tail ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ sq }} ; AGG.MAX LR0 {{ full }} ; INC LR6 1 ;;
    B max_loop ;;
max_tail:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ sq }} ; AGG.MAX LR0 {{ tail }} ;;
    B max_ready ;;
max_single:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ sq }} ; AGG.MAX.FIRST LR0 {{ tail }} ;;
max_ready:
    {{ addr('LR7',6) }}
center_setup:
    ACTIVATE.QUANTIZE identity {{ single }} {{ sq }} {{ cr.temp }} LR0 ; SET LR6 CR0 ;;
    LD.MULT R0 LR0 {{ cr.temp }} ;;
    {{ addr('LR9',6) }}
    LD.MULT.CYCLIC LR9 {{ cr.temp }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ sq }} ; ACC.SUB.FIRST ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ sq }} ; ACC.MAX ;;
    {{ addr('LR9',5) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ sq }} {{ cr.temp }} LR9 ;;
    LD.MULT.CYCLIC LR9 {{ cr.temp }} LR0 ;;
{% macro centered(scale) %}
    LD.MULT R1 LR6 {{ cr.score }} ;;
{% if scale %}
{% for rc in ['LR7','LR2','LR1'] %}
    MULT.RC.VE {{ rc }} LR0 0 LR0 {{ full }} {{ sq }} ; ACC.SUB{{ '.FIRST' if loop.first else '' }} ;;
    MULT.RC.VV {{ rc }} R1 0 LR0 {{ full }} {{ sq }} ; ACC.ADD ;;
{% endfor %}
{% else %}
    MULT.VE LR1 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.ADD.FIRST ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.SUB ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.ADD ;;
{% endif %}
    SET LR9 LR6 ;;
{% for plane in range(2) %}
    ADD LR9 LR9 {{ cr.chunks }} ; LD.MULT R1 LR9 {{ cr.score }} ;;
{% if scale %}
{% for rc in ['LR1','LR2','LR7'] %}
    MULT.RC.VV {{ rc }} R1 0 LR0 {{ full }} {{ sq }} ; ACC.ADD ;;
{% endfor %}
{% else %}
    MULT.VE LR1 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.ADD ;;
{% endif %}
{% endfor %}
{% endmacro %}
refine:
    {{ centered(false) }}
    {{ addr('LR9',7) }}
    LD.MULT R1 LR9 {{ cr.temp }} ;;
    MULT.VE LR1 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.MAX ;;
    SET LR9 LR6 ; BEQ LR6 LR13 refine_tail ;;
{% macro refine_store(ds) %}
{% for i in range(3) %}
    ADD LR9 LR9 {{ cr.chunks }} ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu {{ ds }} {{ sq }} {{ cr.score }} LR9 ;;
    {{ split_score(ds) }}
{% endmacro %}
    {{ refine_store(full) }}
    INC LR6 1 ; B refine ;;
refine_tail:
    {{ refine_store(tail) }}
    ADD LR9 LR9 {{ cr.chunks }} ;;
    SUB LR9 LR9 LR6 ; SET LR6 CR0 ;;
    {{ clear() }}
refine_max:
    LD.MULT R1 LR9 {{ cr.score }} ;;
    MULT.VE LR1 CR1 0 LR0 {{ full }} {{ sq }} ; AGG.MAX LR0 {{ full }} ; INC LR6 1 ; INC LR9 1 ; BLT.S LR6 LR13 refine_max ;;
    DEC LR7 1 ; BNE LR7 CR1 center_setup ;;
    ACTIVATE.QUANTIZE identity {{ single }} {{ sq }} {{ cr.temp }} LR0 ; SET LR6 CR0 ;;
    LD.MULT R0 LR0 {{ cr.temp }} ; SET LR7 LR2 ;;
    INC LR7 128 ;;
exp_loop:
    {{ centered(true) }}
    {{ addr('LR9',4) }}
    LD.MULT R1 LR9 {{ cr.temp }} ;;
    MULT.VE LR1 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.SUB ;;
    BEQ LR6 LR13 exp_tail ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ eq }} {{ cr.score }} LR6 ;;
    INC LR6 1 ; B exp_loop ;;
exp_tail:
    ACTIVATE.QUANTIZE exp2 {{ tail }} {{ eq }} {{ cr.score }} LR6 ;;
    {{ clear() }}
    SET LR6 CR0 ;;
sum_loop:
    LD.MULT.CYCLIC LR6 {{ cr.score }} LR0 ; BEQ LR6 LR13 sum_tail ;;
    MULT.RC.VS LR0 0 LR0 {{ full }} {{ eq }} ; AGG.SUM LR0 {{ full }} ; INC LR6 1 ;;
    B sum_loop ;;
sum_tail:
    MULT.RC.VS LR0 0 LR0 {{ tail }} {{ eq }} ; AGG.SUM LR0 {{ tail }} ;;
    ACTIVATE.QUANTIZE identity {{ single }} {{ sq }} {{ cr.temp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.temp }} ; SET LR7 CR1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ single }} {{ sq }} {{ cr.temp }} LR7 ;;
    LD.MULT R1 LR7 {{ cr.temp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.ADD.FIRST ;;
    MULT.EE LR1 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.ADD ;;
    {{ addr('LR9',8) }}
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ sq }} {{ cr.temp }} LR9 ;;
    LD.MULT.CYCLIC LR9 {{ cr.temp }} LR0 ;;
    {{ addr('LR9',4) }}
    LD.MULT R0 LR9 {{ cr.temp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.ADD.FIRST ;;
{% for i in range(7) %}
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ sq }} ; ACC.ADD ;;
{% endfor %}
    LD.MULT R0 LR0 {{ cr.temp }} ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ sq }} ; ACC.SUB ;;
    MULT.RC.VE LR0 LR1 0 LR0 {{ full }} {{ sq }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ sq }} {{ cr.temp }} LR7 ;;
    LD.MULT R0 LR7 {{ cr.temp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ sq }} ; ACC.ADD.FIRST ;;
    {{ addr('LR9',9) }}
    ACTIVATE.QUANTIZE identity {{ single }} {{ sq }} {{ cr.temp }} LR9 ;;
    {{ addr('LR9',11) }}
    LD.MULT R0 LR9 {{ cr.temp }} ;;
{% for i in [8,9] %}
    {{ addr('LR9',i) }}
    LD.MULT.CYCLIC LR9 {{ cr.temp }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ sq }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ single }} {{ sq }} {{ cr.temp }} LR9 ;;
{% endfor %}
    SET LR6 CR0 ;;
out_loop:
    LD.MULT.CYCLIC LR6 {{ cr.score }} LR0 ; BEQ LR6 LR13 out_tail ;;
{% macro output(ds) %}
    INC LR9 1 ; LD.MULT R0 LR9 {{ cr.temp }} ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ ds }} {{ eq }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ eq }} {{ cr.temp }} LR7 ; DEC LR9 1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.temp }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ eq }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ sq }} {{ cr.temp }} LR7 ;;
    LD.MULT R0 LR7 {{ cr.temp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ sq }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ sq }} {{ cr.temp }} LR0 ;;
    DEC LR9 1 ; LD.MULT R0 LR9 {{ cr.temp }} ;;
    INC LR9 1 ; LD.MULT R1 LR9 {{ cr.temp }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.temp }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ ds }} {{ sq }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 LR1 0 LR0 {{ ds }} {{ sq }} ; ACC.ADD ; LD.MULT.CYCLIC LR0 {{ cr.temp }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ ds }} {{ sq }} ; ACC.ADD ;;
    MULT.RC.VE LR0 LR1 0 LR0 {{ ds }} {{ sq }} ; ACC.ADD ;;
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ sq }} ; ACC.MAX ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endmacro %}
    {{ output(full) }}
    INC LR6 1 ; B out_loop ;;
out_tail:
    {{ output(tail) }}
    ADD LR3 LR3 {{ cr.one }}.L ; INC LR8 1 ; DEC LR11 1 ;;
    BEQ LR11 CR0 done ;;
    BLT.S LR8 LR12 row ;;
    ADD LR5 LR5 LR14 ; SET LR8 CR0 ;;
    BEQ LR5 LR10 group ;;
    SUB LR3 LR3 {{ cr.gaps }}.H ; B row ;;
group:
    ADD LR5 LR5 {{ cr.gaps }}.L ; ADD LR10 LR10 LR15 ; SUB LR3 LR3 {{ cr.one }}.L ;;
    INC LR3 1 ; B row ;;
done:
    HALT ;;
