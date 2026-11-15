{% set nb = s10_channels // 128 %}
{% set M = s10_rows * nb %}
{% macro inc(reg,n) %}
{% for start in range(0,n,255) %}
    INC {{ reg }} {{ [255,n-start]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro loadtmp(row, reg='R0') %}
    SET LR6 CR0 ;;
    INC LR6 {{ row }} ;;
    LD.MULT {{ reg }} LR6 {{ cr.tmp }} ;;
{% endmacro %}
{% macro cyctmp(row) %}
    SET LR6 CR0 ;;
    INC LR6 {{ row }} ;;
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
{% endmacro %}
{% macro split(row) %}
    SET LR6 CR0 ;;
    INC LR6 {{ row }} ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR6 ;;
    LD.MULT R0 LR6 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR6 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR6 ;;
{% endmacro %}
{% macro product(a,b) %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{ cyctmp(a+i) }}
{{ loadtmp(b+j) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
{% endfor %}
{% endmacro %}
{% macro scalesum() %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{ cyctmp(24+i) }}
{{ loadtmp(j) }}
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
{% endfor %}
{% endmacro %}
{% for addr, dest in [('LR10',35),('LR11',36),('LR13',37)] %}
    LD.MULT R0 {{ addr }} CR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR6 CR0 ;;
    INC LR6 {{ dest }} ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR6 ;;
{% endfor %}
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR13 CR0 ;;
    INC LR1 128 ; INC LR12 {{ s0_tokens // 128 }} ; INC LR14 128 ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
token:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% for branch in [0,1] %}
{% for k in range(8 if branch == 0 else 9) %}
{% for side in [0,1] %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if side == 0 else 'ADD' }}.FIRST ;;
{% if branch == 1 %}
    LD.MULT.CYCLIC LR0 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if side == 0 else 'ADD' }} ;;
{% endif %}
{% set bound = (k if k > 0 else -1) if side == 0 else k+1 %}
{% for j in range(bound|abs) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if (side == 0 and bound > 0) or (side == 1 and bound < 0) else 'SUB' }} ;;
{% endfor %}
{% if side == 1 or k == 0 %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    SET LR6 CR{{ side }} ;;
    INC LR6 30 ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR6 ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR6 CR0 ;;
    INC LR6 30 ;;
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR6 1 ;;
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR7 LR15 ;;
    ADD LR7 LR7 LR3 ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L CR0 LR7 ;;
    INC LR3 1 ;;
{% endfor %}
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 token ;;
    SET LR2 CR0 ;;
block:
    SET LR4 CR0 ;;
lane:
    SET LR5 CR0 ; SET LR13 CR0 ;;
    INC LR13 {{ nb }} ;;
channel:
{% for branch in [0,1] %}
    SET LR6 LR2 ; SET LR7 LR5 ;;
    ADD LR6 LR6 LR15 ;;
{% if branch == 1 %}
    INC LR6 8 ;;
{% endif %}
{% for k in range(8 if branch == 0 else 9) %}
    LD.MULT R0 LR6 CR0 ;;
    LD.MULT.CYCLIC LR7 {{ cr.w0 if branch == 0 else cr.w4 }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k == 0 and branch == 0 else '' }} ;;
    INC LR6 1 ; INC LR7 {{ nb }} ;;
{% endfor %}
{% endfor %}
    LD.MULT R1 LR5 {{ cr.aux }} ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.data }} LR8 ;;
    LD.MULT R0 LR8 {{ cr.data }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR6 LR8 ;;
{{ inc('LR6',M) }}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.data }} LR6 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
    INC LR11 1 ; INC LR2 17 ;;
    BLT.S LR11 LR12 block ;;
    SET LR1 CR0 ;;
    INC LR1 128 ;;
    SET LR2 CR0 ; SET LR3 CR0 ;;
{# Refine the quantized reciprocal of the channel count once. #}
{{ cyctmp(35) }}
{{ loadtmp(36) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ split(21) }}
{{ loadtmp(28,'R1') }}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for row in [21,22] %}
{{ loadtmp(row) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    SET LR6 CR0 ;;
    INC LR6 23 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR6 ;;
{{ loadtmp(23) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ split(24) }}
normrow:
    SET LR5 LR2 ; SET LR7 LR2 ;;
    INC LR7 {{ nb }} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
sumloop:
    LD.MULT R0 LR5 {{ cr.data }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    SET LR6 LR5 ;;
{{ inc('LR6',M) }}
    LD.MULT R0 LR6 {{ cr.data }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    INC LR5 1 ;;
    BLT.S LR5 LR7 sumloop ;;
{{ split(0) }}
{{ scalesum() }}
{{ split(6) }}
    SET LR5 LR2 ;;
centerloop:
    LD.MULT R0 LR5 {{ cr.data }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR8 LR5 ;;
{{ inc('LR8',M) }}
    LD.MULT R0 LR8 {{ cr.data }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% for row in [6,7] %}
{{ loadtmp(row) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.data }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.data }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.data }} LR8 ;;
    INC LR5 1 ;;
    BLT.S LR5 LR7 centerloop ;;
    SET LR5 LR2 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
varloop:
    LD.MULT R0 LR5 {{ cr.data }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.data }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    SET LR8 LR5 ;;
{{ inc('LR8',M) }}
    LD.MULT R0 LR8 {{ cr.data }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    LD.MULT.CYCLIC LR8 {{ cr.data }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    INC LR5 1 ;;
    BLT.S LR5 LR7 varloop ;;
{{ split(0) }}
{{ scalesum() }}
{{ loadtmp(37) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR6 CR0 ;;
    INC LR6 8 ;;
    ACTIVATE.QUANTIZE rsqrt CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR6 ;;
{{ split(11) }}
{{ cyctmp(8) }}
{{ loadtmp(8) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ split(13) }}
{{ product(11,13) }}
{{ split(15) }}
{{ cyctmp(8) }}
{% for row in [15,16] %}
{{ loadtmp(row) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
{% endfor %}
{{ split(17) }}
{{ cyctmp(8) }}
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% for row in [17,18] %}
{{ loadtmp(row) }}
    MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
{{ split(19) }}
    SET LR5 LR2 ; SET LR9 CR0 ;;
outloop:
    LD.MULT.CYCLIC LR9 {{ cr.gamma }} LR0 ;;
{% for row in [19,20] %}
{{ loadtmp(row) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
{% endfor %}
{{ split(9) }}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{ cyctmp(9+i) }}
    SET LR8 LR5 ;;
{{ inc('LR8',M if j else 0) }}
    LD.MULT R0 LR8 {{ cr.data }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
{% endfor %}
    LD.MULT R0 LR9 {{ cr.beta }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; INC LR9 1 ;;
    BLT.S LR5 LR7 outloop ;;
    INC LR2 {{ nb }} ; INC LR3 1 ;;
    SET LR6 CR0 ;;
{{ inc('LR6',s10_rows) }}
    BLT.S LR3 LR6 normrow ;;
    HALT ;;
