{% macro ptr(n) %}
    SET LR1 CR0 ;;
    INC LR1 {{ n }} ;;
{% endmacro %}
{% macro save(n) %}
{{ ptr(n) }}
    ACTIVATE.QUANTIZE identity CR15.L CR14.L CR6 LR1 ;;
    LD.MULT R0 LR1 CR6 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L CR14.L CR6 LR1 ;;
{% endmacro %}
{% macro load(n,cyc=false) %}
{{ ptr(n) }}
{% if cyc %}
    LD.MULT.CYCLIC LR1 CR6 LR0 ;;
{% else %}
    LD.MULT R0 LR1 CR6 ;;
{% endif %}
{% endmacro %}
{% macro prod(a,b,first=true,sub=false) %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{ load(a+i,true) }}{{ load(b+j) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.{{ 'SUB' if sub else 'ADD' }}{{ '.FIRST' if first and loop.first else '' }} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ;;
{% for i in range(5) %}
{{ ptr(i) }}
    LD.LUT {{ i }} CR12 LR1 ;;
{% endfor %}
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    SET LR4 CR0 ;;
    SET LR14 CR1 ;;
{% for squared in [false,true] %}
    SET LR5 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
vector_stats_{{ loop.index }}:
{% if squared %}
    LD.MULT.CYCLIC LR5 CR2 LR0 ;;
    MULT.RC.VS LR0 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
{% else %}
    LD.MULT R0 LR5 CR2 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
{% endif %}
    INC LR5 1 ;;
    BLT.S LR5 CR10 vector_stats_{{ loop.index }} ;;
{{ save(34 if squared else 32) }}
{% endfor %}
group_loop:
    MULT.VE LR0 CR0 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
{% for n in [32,33,34,35] %}
{{ load(n) }}
{% if n < 34 %}
    MULT.VE LR3 CR1 0 LR0 CR15.L CR14.L ; AGG.SUM LR0 CR15.H ;;
{% else %}
    MULT.VE LR3 CR1 0 LR0 CR15.L CR14.L ; AGG.SUM LR14 CR15.H ;;
{% endif %}
{% endfor %}
{{ save(0) }}
{% for slot,target in [(0,2),(1,4)] %}
    SET LR6 CR0 ;;
    INC LR6 {{ slot }} ;;
{{ load(0) }}
    MULT.EE LR6 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
{{ load(1) }}
    MULT.EE LR6 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
{{ save(target) }}
{% endfor %}
{% for src,dst in [(2,6),(4,8)] %}
    LD.MULT.CYCLIC LR0 CR8 LR0 ;;
{% for i in range(2) %}
{{ load(src+i) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.ADD{{ '.FIRST' if i==0 else '' }} ;;
{% endfor %}
{{ save(dst) }}
{% endfor %}
{{ load(8) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
{{ load(9) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
{{ prod(6,6,false,true) }}
    LD.MULT R0 LR0 CR9 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
{{ ptr(10) }}
    ACTIVATE.QUANTIZE rsqrt CR15.L CR14.L CR6 LR1 ;;
{{ save(12) }}
    MULT.VE LR0 CR0 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
{{ ptr(11) }}
    ACTIVATE.QUANTIZE identity CR15.L CR14.L CR6 LR1 ;;
{{ prod(10,10) }}{{ save(14) }}
{{ prod(12,14) }}{{ save(16) }}
{{ prod(10,16) }}{{ save(18) }}
{{ load(10) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 CR13 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
{% for n in [18,19] %}
{{ load(n) }}
    MULT.VE LR0 CR13 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
{% endfor %}
{{ save(20) }}
{% for n in [6,7,20,21] %}
{{ load(n) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L CR14.L CR7 LR4 ;;
    INC LR4 1 ;;
{% endfor %}
    INC LR2 1 ;;
    INC LR3 {{ 128//rows }} ;;
    SET LR6 CR0 ;;
    INC LR6 {{ rows }} ;;
    BLT.S LR2 LR6 group_loop ;;
{% for component in range(4) %}
    SET LR8 CR0 ;;
    SET LR9 CR0 ;;
    SET LR10 CR0 ;;
    SET LR11 CR0 ;;
    SET LR2 CR0 ;;
    SET LR4 CR0 ;;
    INC LR4 {{ component }} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
merge_{{ component }}:
    LD.MULT R0 LR4 CR7 ;;
{% for lane in range(128//rows) %}
    MULT.EE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.RESHAPE LRD10 LRD8 7 ;;
    ADDBI LRD8 1 ;;
{% endfor %}
    INC LR4 4 ;;
    INC LR2 1 ;;
    BLT.S LR2 LR6 merge_{{ component }} ;;
{{ ptr(24+component) }}
    ACTIVATE.QUANTIZE identity CR15.L CR14.L CR6 LR1 ;;
{% endfor %}
    SET LR5 CR0 ;;
out_loop:
    LD.MULT R0 LR5 CR2 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
{% for n in [24,25] %}
{{ load(n) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
{% endfor %}
{{ save(28) }}
{{ prod(28,26) }}{{ save(30) }}
    LD.MULT.CYCLIC LR5 CR3 LR0 ;;
{% for n in [30,31] %}
{{ load(n) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.ADD{{ '.FIRST' if n==30 else '' }} ;;
{% endfor %}
    LD.MULT R0 LR5 CR4 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE generic CR15.L CR14.L CR5 LR5 ;;
    INC LR5 1 ;;
    BLT.S LR5 CR10 out_loop ;;
    HALT ;;
