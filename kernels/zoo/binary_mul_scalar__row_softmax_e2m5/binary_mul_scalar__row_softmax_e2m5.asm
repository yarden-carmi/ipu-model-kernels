{% set q = cr.qf ~ '.L' %}
{% macro mv(acc='ACC.ADD.FIRST', scale='CR1') %}
    MULT.VE LR0 {{ scale }} 0 LR0 CR15.L {{ q }} ; {{ acc }} ;;
{% endmacro %}
{% macro vv(acc='ACC.ADD.FIRST', idx='LR0') %}
    MULT.RC.VV {{ idx }} R0 0 LR0 CR15.L {{ q }} ; {{ acc }} ;;
{% endmacro %}
{% macro store(base, idx='LR1', fn='identity') %}
    ACTIVATE.QUANTIZE {{ fn }} CR15.L {{ q }} {{ cr[base] }} {{ idx }} ;;
{% endmacro %}
{% macro load(base, idx='LR1') %}
    LD.MULT R0 {{ idx }} {{ cr[base] }} ;;
{% endmacro %}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR7 CR1 ;;
    SET LR8 CR0 ;;
    INC LR8 2 ;;
row_loop:
    SET LR3 CR0 ;;
exp_loop:
{{ load('operand', 'LR0') }}
{{ mv(scale=cr.scale) }}
    SET LR1 CR0 ;;
    INC LR1 3 ;;
{{ store('poly') }}
{{ load('poly') }}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ q }} ; ACC.ADD.FIRST ;;
    SET LR1 CR0 ;;
{{ store('poly') }}
{{ load('poly') }}
{{ mv('ACC.SUB') }}
    SET LR1 CR0 ;;
    INC LR1 3 ;;
{{ store('poly') }}
    SET LR10 CR0 ;;
    INC LR10 128 ;;
    INC LR10 128 ;;
    LD.MULT.CYCLIC LR1 {{ cr.poly }} LR10 ;;
    SET LR1 CR0 ;;
    LD.MULT.CYCLIC LR1 {{ cr.poly }} LR0 ;;
{{ load('c5', 'LR0') }}
{{ mv() }}
{% for coeff in ['c4','c3','c2','one','one'] %}
    SET LR1 CR1 ;;
{{ store('poly') }}
{{ load('poly') }}
{{ mv('ACC.SUB') }}
    INC LR1 1 ;;
{{ store('poly') }}
{{ load('poly') }}
{{ vv() }}
{{ vv('ACC.ADD', 'LR10') }}
    SET LR1 CR1 ;;
{{ load('poly') }}
{{ vv('ACC.ADD') }}
{{ vv('ACC.ADD', 'LR10') }}
{% if coeff == 'one' %}
    SET LR1 CR0 ;;
    INC LR1 7 ;;
{{ load('tmp') }}
{% else %}
{{ load(coeff, 'LR0') }}
{% endif %}
{{ mv('ACC.ADD') }}
{% endfor %}
{% for square in range(6) %}
    SET LR1 CR1 ;;
{{ store('poly') }}
{{ load('poly') }}
{{ mv('ACC.SUB') }}
    INC LR1 1 ;;
{{ store('poly') }}
    SET LR1 CR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.poly }} LR0 ;;
{{ load('poly') }}
{{ vv() }}
    INC LR1 1 ;;
{{ load('poly') }}
{{ vv('ACC.ADD') }}
{{ vv('ACC.ADD') }}
{% endfor %}
{{ store('exps', 'LR3') }}
{{ load('exps', 'LR3') }}
{{ mv('ACC.SUB') }}
    SET LR5 LR3 ;;
    INC LR5 2 ;;
{{ store('exps', 'LR5') }}
    INC LR2 1 ;;
    INC LR3 1 ;;
    BLT.S LR3 LR8 exp_loop ;;
{{ mv(scale='CR0') }}
{% for j in range(4) %}
    SET LR1 CR0 ;;
    INC LR1 {{ j }} ;;
{{ load('exps') }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
{% endfor %}
{{ store('tmp', 'LR0') }}
{{ load('tmp', 'LR0') }}
{{ mv('ACC.SUB') }}
{{ store('tmp', 'LR7') }}
    LD.MULT R1 LR7 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD.FIRST ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD ;;
{{ store('tmp', 'LR8', 'reciprocal') }}
    SET LR1 CR0 ;;
    INC LR1 3 ;;
{{ store('tmp') }}
{{ load('tmp') }}
{{ mv('ACC.SUB') }}
    INC LR1 1 ;;
{{ store('tmp') }}
    LD.MULT.CYCLIC LR8 {{ cr.tmp }} LR0 ;;
    SET LR1 CR0 ;;
    INC LR1 7 ;;
{{ load('tmp') }}
{{ mv() }}
{% for j in [3,4] %}
    SET LR1 CR0 ;;
    INC LR1 {{ j }} ;;
{{ load('tmp') }}
{{ vv('ACC.SUB') }}
{% endfor %}
    SET LR1 CR0 ;;
    INC LR1 5 ;;
{{ store('tmp') }}
{{ load('tmp') }}
{{ vv() }}
    INC LR1 1 ;;
{{ store('tmp') }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR9 ;;
    SET LR3 CR0 ;;
    SET LR4 LR2 ;;
    SUB LR4 LR4 LR8 ;;
out_loop:
{{ load('exps', 'LR3') }}
{{ vv() }}
{{ vv('ACC.ADD', 'LR9') }}
    SET LR5 LR3 ;;
    INC LR5 2 ;;
{{ load('exps', 'LR5') }}
{{ vv('ACC.ADD') }}
{{ vv('ACC.ADD', 'LR9') }}
{{ store('out0', 'LR4') }}
    INC LR4 1 ;;
    INC LR3 1 ;;
    BLT.S LR3 LR8 out_loop ;;
    BLT.S LR2 {{ cr.M }} row_loop ;;
    HALT ;;
