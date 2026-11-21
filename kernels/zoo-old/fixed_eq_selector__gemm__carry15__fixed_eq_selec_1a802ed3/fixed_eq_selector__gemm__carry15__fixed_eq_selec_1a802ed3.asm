{% set nt = s0_tokens // 128 %}
{% set M = s10_rows * 6 %}
{% set E = 16 * nt + 2 %}
{% set A = E + 2 * M %}
{% set T = A + M %}
{% macro integer(r,n) %}
    SET {{ r }} CR0 ;;
{% for v in range(n // 128) %}
    INC {{ r }} 128 ;;
{% endfor %}
    INC {{ r }} {{ n % 128 }} ;;
{% endmacro %}
{% macro idx(i) %}
    SET LR1 LR10 ;;
    INC LR1 {{ i }} ;;
{% endmacro %}
{% macro ra(i, r='R0') %}
{{ idx(i) }}
    LD.MULT {{ r }} LR1 {{ cr.work }} ;;
{% endmacro %}
{% macro rc(i, slot='LR0') %}
{{ idx(i) }}
    LD.MULT.CYCLIC LR1 {{ cr.work }} {{ slot }} ;;
{% endmacro %}
{% macro store(i) %}
{{ idx(i) }}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
{% endmacro %}
{% macro pair(i) %}
{{ store(i) }}
    LD.MULT R0 LR1 {{ cr.work }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ store(i+1) }}
{% endmacro %}
{% macro product(a,b,d) %}
{{ rc(a) }}
{{ ra(b) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ ra(b+1) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ rc(a+1) }}
{{ ra(b) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ ra(b+1) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ pair(d) }}
{% endmacro %}
{% macro scale(a,d) %}
    LD.MULT.CYCLIC LR13 CR0 LR0 ;;
{{ ra(a) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ ra(a+1) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    LD.MULT.CYCLIC LR14 CR0 LR0 ;;
{{ ra(a) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ ra(a+1) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ pair(d) }}
{% endmacro %}
    INC LR1 128 ; INC LR11 1 ; INC LR10 {{ nt }} ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
{% for stage in range(2) %}
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    INC LR3 {{ stage * nt * 8 }} ;;
tokens{{ stage }}:
    LD.MULT R0 LR2 {{ cr.in0 if stage == 0 else cr.in1 }} ;;
{% for k in range(8) %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in range(k + stage) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
{% if stage == 1 %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
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
    INC LR3 2 ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.work }} LR3 ;;
    DEC LR3 1 ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR10 tokens{{ stage }} ;;
{% endfor %}
{% for stage in range(2) %}
{{ integer('LR2',2 + stage * nt * 8) }}
{{ integer('LR8',E + stage * M) }}
    SET LR9 CR0 ;;
block{{ stage }}:
    SET LR4 CR0 ;;
lane{{ stage }}:
    SET LR5 CR0 ;;
channel{{ stage }}:
    SET LR6 LR2 ; SET LR7 LR5 ;;
{% if stage == 1 %}
    INC LR7 6 ;;
{% endif %}
{% for k in range(8) %}
    LD.MULT R0 LR6 {{ cr.work }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w0 if stage == 0 else cr.w1 }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k == 0 else '' }} ;;
    INC LR6 1 ; INC LR7 6 ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
{{ integer('LR12',6) }}
    BLT.S LR5 LR12 channel{{ stage }} ;;
    INC LR4 1 ;;
{{ integer('LR12',128) }}
    BLT.S LR4 LR12 lane{{ stage }} ;;
    INC LR9 1 ; INC LR2 8 ;;
    BLT.S LR9 LR10 block{{ stage }} ;;
{% endfor %}
{{ integer('LR2',E) }}
{{ integer('LR4',E+M) }}
{{ integer('LR8',A) }}
    SET LR5 CR0 ; SET LR9 CR0 ;;
add:
    LD.MULT R0 LR2 {{ cr.work }} ;;
    LD.MULT R1 LR4 {{ cr.work }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR8 ;;
    LD.MULT R0 LR8 {{ cr.work }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.v }} LR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR8 ;;
    INC LR2 1 ; INC LR4 1 ; INC LR8 1 ;;
    INC LR9 1 ; INC LR5 1 ;;
{{ integer('LR12',6) }}
    BLT.S LR5 LR12 add_continue ;;
    SET LR5 CR0 ;;
add_continue:
{{ integer('LR12',M) }}
    BLT.S LR9 LR12 add ;;
{{ integer('LR2',A) }}
{{ integer('LR10',T) }}
{{ integer('LR3',128) }}
{{ integer('LR4',256) }}
    SET LR7 CR1 ;;
    SET LR8 CR0 ;;
row:
    SET LR5 LR2 ; SET LR6 LR2 ;;
    INC LR6 6 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
stats:
    LD.MULT R0 LR5 {{ cr.work }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.work }} LR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
    INC LR5 1 ;;
    BLT.S LR5 LR6 stats ;;
{{ pair(0) }}
    LD.MULT R0 LR1 {{ cr.work }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ store(26) }}
{% for lane, dest in [(0,2),(1,4)] %}
{{ ra(0) }}
    MULT.EE {{ 'LR0' if lane==0 else 'LR7' }} CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ ra(1) }}
    MULT.EE {{ 'LR0' if lane==0 else 'LR7' }} CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ ra(26) }}
    MULT.EE {{ 'LR0' if lane==0 else 'LR7' }} CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ pair(dest) }}
{% endfor %}
{{ scale(2,6) }}
{{ scale(4,10) }}
{{ rc(6) }}
{{ ra(6) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ ra(7) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ rc(7) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ pair(28) }}
{{ ra(10) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ ra(11) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ ra(28) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ ra(29) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT R0 LR15 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ idx(12) }}
    ACTIVATE.QUANTIZE rsqrt CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
{{ pair(10) }}
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ store(13) }}
{{ product(12,12,14) }}
{{ product(10,14,16) }}
{{ product(12,16,18) }}
{{ ra(12) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ ra(18) }}
    MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ ra(19) }}
    MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ pair(20) }}
    SET LR5 LR2 ; SET LR9 CR0 ;;
output:
    LD.MULT.CYCLIC LR9 {{ cr.gamma }} LR0 ;;
{{ ra(20) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ ra(21) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ pair(22) }}
    LD.MULT R0 LR1 {{ cr.work }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ store(24) }}
    LD.MULT.CYCLIC LR5 {{ cr.work }} LR0 ;;
{{ rc(6,'LR3') }}
{{ rc(7,'LR4') }}
{% for k in [22,23,24] %}
{{ ra(k) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k==22 else '' }} ;;
    MULT.RC.VV LR3 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.RC.VV LR4 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    LD.MULT R0 LR9 {{ cr.beta }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ; INC LR9 1 ;;
    BLT.S LR5 LR6 output ;;
    SET LR2 LR6 ;;
{{ integer('LR12',A+M) }}
    BLT.S LR2 LR12 row ;;
    HALT ;;
