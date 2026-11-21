{% set nb = s1_n // 128 %}
{% set ntb = s0_tokens // 128 %}
{% macro load(r) %}
    SET LR10 CR0 ;;
    INC LR10 {{ r }} ;;
    LD.MULT R0 LR10 {{ cr.work }} ;;
{% endmacro %}
{% macro cyc(r) %}
    SET LR10 CR0 ;;
    INC LR10 {{ r }} ;;
    LD.MULT.CYCLIC LR10 {{ cr.work }} LR0 ;;
{% endmacro %}
{% macro save(r) %}
{% for j in range(3) %}
    SET LR10 CR0 ;;
    INC LR10 {{ r+j }} ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR10 ;;
{% if j < 2 %}
    LD.MULT R0 LR10 {{ cr.work }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro product(a,b,first=true,subtract=false) %}
{% for i in range(3) %}
{{ cyc(a+i) }}
{% for j in range(3) %}
{{ load(b+j) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if subtract else 'ADD' }}{{ '.FIRST' if first and i==0 and j==0 else '' }} ;;
{% endfor %}
{% endfor %}
{% endmacro %}
    INC LR1 128 ; INC LR11 1 ; INC LR12 {{ ntb }} ;;
    INC LR13 {{ nb }} ; INC LR14 128 ;;
    INC LR10 63 ;;
    LD.MULT R1 LR10 {{ cr.work }} ;;
tokens:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% for k in range(8) %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in range(k+1) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR0 ;;
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR11 ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT.CYCLIC LR11 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
    INC LR3 1 ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 tokens ;;
    SET LR2 CR0 ;;
block:
    SET LR4 CR0 ;;
lane:
    SET LR5 CR0 ;;
channel:
    SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(8) %}
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k == 0 else '' }} ;;
    INC LR6 1 ; INC LR7 {{ nb }} ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.x }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
    INC LR9 1 ; INC LR2 8 ;;
    BLT.S LR9 LR12 block ;;
    SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR7 CR1 ;;
    SET LR8 CR0 ;;
{% for off in range(0,s2_rows,255) %}
    INC LR8 {{ [255,s2_rows-off]|min }} ;;
{% endfor %}
    SET LR9 CR0 ;;
    INC LR9 {{ nb }} ;;
norm:
    SET LR4 LR2 ; SET LR5 CR0 ;;
{{ load(63) }}
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
stats:
    LD.MULT R0 LR4 {{ cr.x }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.x }} LR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
    INC LR4 1 ; INC LR5 1 ;;
    BLT.S LR5 LR9 stats ;;
{{ save(0) }}
{% for stat in range(2) %}
{% for j in range(3) %}
{{ load(j) }}
    MULT.EE {{ 'LR0' if stat==0 else 'LR7' }} CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if j==0 else '' }} ;;
{% endfor %}
{{ save(3+stat*3) }}
{% endfor %}
    LD.MULT R0 LR0 {{ cr.c }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ save(9) }}
{# C*c by repeated addition, then c*(2-C*c). #}
    LD.MULT R0 LR0 {{ cr.c }} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR6 CR0 ;;
    SET LR13 CR0 ;;
{% for off in range(0,s2_channels,255) %}
    INC LR13 {{ [255,s2_channels-off]|min }} ;;
{% endfor %}
recip_count:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR6 1 ;;
    BLT.S LR6 LR13 recip_count ;;
{{ save(27) }}
{{ load(63) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% for j in range(3) %}
{{ load(27+j) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
{{ save(30) }}
{{ product(9,30) }}
{{ save(9) }}
{{ product(3,9) }}
{{ save(12) }}
{{ product(6,9) }}
{{ product(12,12,false,true) }}
    LD.MULT R0 LR0 {{ cr.epsilon }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ save(15) }}
{% for j in range(3) %}
{{ load(15+j) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if j==0 else '' }} ;;
{% endfor %}
    SET LR10 CR0 ;;
    INC LR10 18 ;;
    ACTIVATE.QUANTIZE rsqrt CR15.L {{ cr.qf }}.L {{ cr.work }} LR10 ;;
    LD.MULT R0 LR10 {{ cr.work }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ save(18) }}
{{ product(18,18) }}
{{ save(27) }}
{{ product(15,27) }}
{{ save(30) }}
{{ load(63) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% for j in range(3) %}
{{ load(30+j) }}
    MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
{{ save(33) }}
{{ product(18,33) }}
{{ save(18) }}
    SET LR4 LR2 ; SET LR5 CR0 ;;
output:
    LD.MULT R0 LR4 {{ cr.x }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in range(3) %}
{{ load(12+j) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
{{ save(21) }}
{{ product(21,18) }}
{{ save(24) }}
    LD.MULT.CYCLIC LR5 {{ cr.gamma }} LR0 ;;
{% for j in range(3) %}
{{ load(24+j) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if j==0 else '' }} ;;
{% endfor %}
    LD.MULT R0 LR5 {{ cr.beta }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; INC LR5 1 ;;
    BLT.S LR5 LR9 output ;;
    INC LR3 1 ; ADD LR2 LR2 LR9 ;;
    BLT.S LR3 LR8 norm ;;
    HALT ;;
