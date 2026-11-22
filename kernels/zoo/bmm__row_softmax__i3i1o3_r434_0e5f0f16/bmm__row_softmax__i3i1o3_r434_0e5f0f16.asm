{% set full = cr.width ~ '.L' %}
{% set tail = cr.width ~ '.H' %}
{% set score = cr.workq ~ '.L' %}
{% set expq = cr.workq ~ '.H' %}
{% set single = cr.one ~ '.H' %}
{% macro coefficient(slot, power, count, cyclic) %}
    LD.MULT R0 LR0 {{ cr.temp }} ; SET LR6 CR0 ; SET LR7 CR0 ;;
    INC LR6 {{ power }} ; INC LR7 {{ slot }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ score }} ; ACC.ADD.FIRST ;;
coef_pow_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ score }} ; ACC.SUB ; DEC LR6 1 ; BNE LR6 CR0 coef_pow_{{ slot }} ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ score }} {{ cr.temp }} LR7 ;;
    LD.MULT R0 LR7 {{ cr.temp }} ; INC LR6 {{ count }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ score }} ; ACC.ADD.FIRST ;;
coef_sum_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ score }} ; ACC.ADD ; DEC LR6 1 ; BNE LR6 CR0 coef_sum_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ score }} {{ cr.temp }} LR7 ;;
    LD.MULT.CYCLIC LR7 {{ cr.temp }} {{ cyclic }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR8 CR0 ;;
    LD.MULT R0 LR0 {{ cr.in0 }} ; INC LR1 128 ; INC LR2 128 ;;
    INC LR2 128 ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ score }} {{ cr.temp }} LR0 ;;
    SET LR9 LR2 ;;
    INC LR9 128 ;;
    {{ coefficient(1, 4, 23, 'LR1') }}
    {{ coefficient(2, 12, 21, 'LR2') }}
    {{ coefficient(3, 19, 36, 'LR9') }}

row:
    SET LR6 CR0 ;;
tile:
    ADD LR7 LR5 LR6 ; SET LR9 CR0 ;;
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
{% macro product(first) %}
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 LR9 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR7 LR7 {{ cr.chunks }} ;;
    INC LR9 1 ;;
{% endmacro %}
    {{ product(true) }}
    BGE.S LR9 {{ cr.s0_k }} score_store ;;
kloop:
    {{ product(false) }}
    BLT.S LR9 {{ cr.s0_k }} kloop ;;
score_store:
    BEQ LR6 LR13 score_tail ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ score }} {{ cr.score }} LR6 ;;
    INC LR6 1 ; B tile ;;
score_tail:
    ACTIVATE.QUANTIZE identity {{ tail }} {{ score }} {{ cr.score }} LR6 ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;

{% macro reduce(op, q) %}
    SET LR6 CR0 ;;
{{ op }}_loop:
    {% if op == 'MAX' %}LD.MULT R0 LR6 {{ q }}{% else %}LD.MULT.CYCLIC LR6 {{ q }} LR0{% endif %} ; BEQ LR6 LR13 {{ op }}_tail ;;
    {% if op == 'MAX' %}MULT.VE LR0 CR1 0 LR0 {{ full }} {{ score }}{% else %}MULT.RC.VS LR0 0 LR0 {{ full }} {{ expq }}{% endif %} ; AGG.{{ op }} LR0 {{ full }} ; INC LR6 1 ;;
    B {{ op }}_loop ;;
{{ op }}_tail:
    {% if op == 'MAX' %}MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ score }}{% else %}MULT.RC.VS LR0 0 LR0 {{ tail }} {{ expq }}{% endif %} ; AGG.{{ op }} LR0 {{ tail }} ;;
{% endmacro %}
    LD.MULT R0 LR0 {{ cr.score }} ; BEQ LR13 CR0 max_single ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ score }} ; AGG.MAX.FIRST LR0 {{ full }} ;;
    {{ reduce('MAX', cr.score) }}
    B max_ready ;;
max_single:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ score }} ; AGG.MAX.FIRST LR0 {{ tail }} ;;
max_ready:
    ACTIVATE.QUANTIZE identity {{ single }} {{ score }} {{ cr.temp }} LR0 ; SET LR6 CR0 ;;
    LD.MULT R0 LR0 {{ cr.temp }} ; SET LR7 LR2 ;;
    INC LR7 128 ;;
exp_loop:
    LD.MULT R1 LR6 {{ cr.score }} ;;
{% for rc in ['LR7','LR2','LR1'] %}
    MULT.RC.VE {{ rc }} LR0 0 LR0 {{ full }} {{ score }} ; ACC.SUB{{ '.FIRST' if loop.first else '' }} ;;
    MULT.RC.VV {{ rc }} R1 0 LR0 {{ full }} {{ score }} ; ACC.ADD ;;
{% endfor %}
    BEQ LR6 LR13 exp_tail ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ expq }} {{ cr.score }} LR6 ;;
    INC LR6 1 ; B exp_loop ;;
exp_tail:
    ACTIVATE.QUANTIZE exp2 {{ tail }} {{ expq }} {{ cr.score }} LR6 ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ score }} ; ACC.ADD.FIRST ;;
    {{ reduce('SUM', cr.score) }}
    ACTIVATE.QUANTIZE rsqrt {{ single }} {{ expq }} {{ cr.temp }} LR0 ; SET LR6 CR0 ;;
    LD.MULT R0 LR0 {{ cr.temp }} ; SET LR7 CR1 ;;
out_loop:
    LD.MULT.CYCLIC LR6 {{ cr.score }} LR0 ; BEQ LR6 LR13 out_tail ;;
{% macro output(ds) %}
    MULT.RC.VE LR0 LR0 0 LR0 {{ ds }} {{ expq }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ expq }} {{ cr.temp }} LR7 ;;
    LD.MULT.CYCLIC LR7 {{ cr.temp }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ expq }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
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
