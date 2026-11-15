{% macro ptr(r,n) %}
    SET {{ r }} CR0 ;;
{{ inc(r,n) }}
{% endmacro %}
{% macro inc(r,n) %}
{% for i in range(n // 255) %}
    INC {{ r }} 255 ;;
{% endfor %}
    INC {{ r }} {{ n % 255 }} ;;
{% endmacro %}
{% macro save(n) %}
{{ ptr('LR1',n) }}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR9 CR0 ;;
row:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
{{ save(0) }}
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{{ ptr('LR3',128) }}
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ save(2) }}
    DEC LR1 1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.recip }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR0 {{ cr.rlo }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    LD.MULT R0 LR0 {{ cr.rtiny }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR1 1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.recip }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    LD.MULT R0 LR0 {{ cr.epsilon }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ ptr('LR1',4) }}
    ACTIVATE.QUANTIZE rsqrt CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{{ save(8) }}
{{ ptr('LR1',4) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ save(10) }}
{{ ptr('LR1',8) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
{{ ptr('LR1',10) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ ptr('LR1',9) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
{{ ptr('LR1',10) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ save(12) }}
{{ ptr('LR1',4) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
{{ ptr('LR1',12) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ save(14) }}
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    DEC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ save(4) }}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    DEC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ save(6) }}
    LD.MULT R0 LR0 {{ cr.gamma }} ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    DEC LR1 1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.norm }} LR9 ;;
    LD.MULT R0 LR9 {{ cr.norm }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR9 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.norm }} LR9 ;;
    LD.MULT R0 LR9 {{ cr.norm }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR9 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.norm }} LR9 ;;
    INC LR9 1 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.rows }} row ;;
    SET LR2 CR0 ;;
    SET LR9 CR0 ;;
    SET LR10 CR0 ;;
    SET LR11 CR0 ;;
{{ ptr('LR13',128*channels*3) }}
height:
    SET LR3 CR0 ;;
width:
    SET LR12 CR0 ;;
    SET LR14 CR0 ;;
block:
{{ ptr('LR5',128) }}
{{ ptr('LR15',(rows//channels+127)//128-1) }}
    BLT.S LR14 LR15 fullblock ;;
{{ ptr('LR5', (rows//channels-1)%128+1) }}
fullblock:
{% for part in range(3) %}
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ADD LR4 LR2 LR12 ;;
    INC LR4 {{ part }} ;;
    SET LR6 CR0 ;;
    SET LR7 CR0 ;;
    SET LR8 CR0 ;;
transpose_{{ part }}:
    LD.MULT R0 LR4 {{ cr.norm }} ;;
    MULT.EE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.RESHAPE LRD10 LRD6 7 ;;
{{ inc('LR4', channels * 3) }}
    ADDBI LRD6 1 ;;
    INC LR8 1 ;;
    BLT.S LR8 LR5 transpose_{{ part }} ;;
{{ ptr('LR1',part) }}
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.H {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{% endfor %}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR1 CR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE relu {{ cr.tail }}.H {{ cr.qf }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ;;
    ADD LR12 LR12 LR13 ;;
    INC LR14 1 ;;
{{ ptr('LR15',(rows//channels+127)//128) }}
    BLT.S LR14 LR15 block ;;
    INC LR3 1 ;;
{{ ptr('LR5', channels) }}
    BLT.S LR3 LR5 width ;;
    INC LR2 3 ;;
{{ ptr('LR5', channels*3) }}
    BLT.S LR2 LR5 height ;;
    HALT ;;
