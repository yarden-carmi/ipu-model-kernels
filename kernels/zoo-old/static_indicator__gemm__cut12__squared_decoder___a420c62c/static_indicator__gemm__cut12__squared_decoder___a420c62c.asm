{% set ke = [s0_vocab, 8]|min %}
{% set nb = s1_n // 128 %}
{# pair operations use LR0=0, LR1=128, LR10/11 as temporary addresses #}
{% macro addr(i, reg='LR10') %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ i }} ;;
{% endmacro %}
{% macro save(i) %}
{{ addr(i) }}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR10 ;;
    LD.MULT R0 LR10 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR10 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR10 ;;
{% endmacro %}
{% macro pair(a, sign='ADD', first=false, scale='CR1') %}
{% for j in range(2) %}
{{ addr(a+j) }}
    LD.MULT R0 LR10 {{ cr.tmp }} ;;
    MULT.VE LR0 {{ scale }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ sign }}{{ '.FIRST' if first and j==0 else '' }} ;;
{% endfor %}
{% endmacro %}
{% macro prod(a,b,sign='ADD',first=false) %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{ addr(a+i) }}
    LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ;;
{{ addr(b+j) }}
    LD.MULT R0 LR10 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ sign }}{{ '.FIRST' if first and i==0 and j==0 else '' }} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    INC LR1 128 ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
    LD.MULT R0 LR15 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ addr(36) }}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR10 ;;
    LD.MULT.CYCLIC LR13 CR0 LR0 ;;
    LD.MULT R0 LR14 CR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ save(32) }}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ pair(32, 'SUB') }}
{{ save(34) }}
    LD.MULT.CYCLIC LR13 CR0 LR0 ;;
{% for i in range(2) %}
{{ addr(34+i) }}
    LD.MULT R0 LR10 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if i==0 else '' }} ;;
{% endfor %}
{{ save(30) }}
    SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR12 CR0 ;;
    INC LR12 {{ s0_tokens // 128 }} ;;
    SET LR11 CR1 ;;
selectors_loop:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% for k in range(ke) %}
{% for boundary in [k,k+1] %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
{% for j in range(boundary) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR11 ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR11 ;;
{% if boundary==k %}
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR1 ;;
{% endif %}
{% endfor %}
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
    INC LR3 1 ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 selectors_loop ;;
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    SET LR8 CR0 ;;
    SET LR13 CR0 ;;
    INC LR13 {{ nb }} ;;
    SET LR14 CR0 ;;
    INC LR14 128 ;;
embed_block:
    SET LR4 CR0 ;;
embed_token:
    SET LR5 CR0 ;;
embed_channel:
    SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(ke) %}
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k==0 else '' }} ;;
    INC LR6 1 ; INC LR7 {{ nb }} ;;
{% endfor %}
{{ addr(38) }}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR10 ;;
{% for repeat in range(2) %}
    LD.MULT R0 LR10 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR5 {{ cr.table }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR10 ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.x }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 embed_channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 embed_token ;;
    INC LR3 1 ; INC LR2 {{ ke }} ;;
    BLT.S LR3 LR12 embed_block ;;
    SET LR2 CR0 ;;
    SET LR12 CR0 ;;
{% for i in range(s9_rows * nb // 128) %}
    INC LR12 128 ;;
{% endfor %}
normalize:
    SET LR5 LR2 ; SET LR6 LR2 ;;
    INC LR6 {{ nb }} ;;
    SET LR7 CR1 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
stats:
    LD.MULT R0 LR5 {{ cr.x }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.x }} LR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
    INC LR5 1 ;;
    BLT.S LR5 LR6 stats ;;
{{ save(0) }}
{% for lane,target in [(0,2),(1,4)] %}
{% for j in range(2) %}
{{ addr(j) }}
    LD.MULT R0 LR10 {{ cr.tmp }} ;;
    SET LR11 CR0 ;;
    INC LR11 {{ lane }} ;;
    MULT.EE LR11 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if j==0 else '' }} ;;
{% endfor %}
{{ save(target) }}
{% endfor %}
{{ prod(2,30,first=true) }}
{{ save(6) }}
{{ prod(4,30,first=true) }}
{{ prod(6,6,'SUB') }}
{{ addr(36) }}
    LD.MULT R0 LR10 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ addr(8) }}
    ACTIVATE.QUANTIZE rsqrt CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR10 ;;
{{ save(10) }}
{{ addr(8) }}
    LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR10 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ save(12) }}
{{ prod(10,12,first=true) }}
{{ save(14) }}
{{ addr(8) }}
    LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ;;
{% for j in range(2) %}
{{ addr(14+j) }}
    LD.MULT R0 LR10 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if j==0 else '' }} ;;
{% endfor %}
{{ save(16) }}
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ pair(16,'SUB',scale=cr.half) }}
{{ save(18) }}
    SET LR5 LR2 ; SET LR7 CR0 ;;
norm_chunk:
    LD.MULT R0 LR5 {{ cr.x }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ pair(6,'SUB') }}
{{ save(20) }}
{{ prod(20,18,first=true) }}
{{ save(22) }}
    LD.MULT.CYCLIC LR7 {{ cr.gamma }} LR0 ;;
{% for j in range(2) %}
{{ addr(22+j) }}
    LD.MULT R0 LR10 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if j==0 else '' }} ;;
{% endfor %}
    LD.MULT R0 LR7 {{ cr.beta }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.x }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.x }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.xlo }} LR5 ;;
    INC LR5 1 ; INC LR7 1 ;;
    BLT.S LR5 LR6 norm_chunk ;;
    SET LR2 LR6 ;;
    BLT.S LR2 LR12 normalize ;;
{# Transpose into channel-major output, one element via byte-broadcast reshape. #}
    SET LR0 CR0 ; SET LR1 CR0 ;;
    SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ;;
    SET LR12 CR0 ;;
{% for i in range(s9_channels // 128) %}
    INC LR12 128 ;;
{% endfor %}
    SET LR13 CR0 ;;
    INC LR13 {{ s9_rows // 128 }} ;;
    SET LR14 CR0 ;;
    INC LR14 128 ;;
    SET LR8 CR0 ;;
    SET LR15 CR0 ;;
transpose_channel:
    SET LR9 CR0 ; SET LR10 LR4 ;;
transpose_block:
{% for part in ['x','xlo'] %}
    SET LR10 LR4 ;;
{% if s9_rows // 128 > 1 %}
    BLT.S LR9 CR1 transpose_start_{{ part }} ;;
{% for i in range(nb) %}
    INC LR10 128 ;;
{% endfor %}
transpose_start_{{ part }}:
{% endif %}
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR11 CR0 ;;
transpose_lane_{{ part }}:
    LD.MULT R0 LR10 {{ cr[part] }} ;;
    MULT.VE LR15 CR1 0 LR15 CR15.L {{ cr.qf }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADDBI LRD2 1 ;;
    INC LR10 {{ nb }} ; INC LR11 1 ;;
    BLT.S LR11 LR14 transpose_lane_{{ part }} ;;
{% if part == 'x' %}
    SET LR7 CR0 ;;
    INC LR7 38 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR7 ;;
    LD.MULT R0 LR7 {{ cr.tmp }} ;;
    MULT.VE LR15 CR1 0 LR15 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR7 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR7 ;;
    DEC LR7 1 ;;
{% else %}
    LD.MULT R0 LR7 {{ cr.tmp }} ;;
    MULT.VE LR15 CR1 0 LR15 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR7 1 ;;
    LD.MULT R0 LR7 {{ cr.tmp }} ;;
    MULT.VE LR15 CR1 0 LR15 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; INC LR9 1 ;;
    BLT.S LR9 LR13 transpose_block ;;
    ADDBI LRD0 1 ;;
    INC LR5 1 ;;
    INC LR6 1 ;;
    BLT.S LR6 LR14 transpose_next ;;
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR6 CR0 ;;
    INC LR4 1 ;;
transpose_next:
    BLT.S LR5 LR12 transpose_channel ;;
    HALT ;;
