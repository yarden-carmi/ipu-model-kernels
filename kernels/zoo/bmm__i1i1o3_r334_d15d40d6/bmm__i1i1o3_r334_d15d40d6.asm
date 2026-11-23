{# Two consecutive K columns per input row. In the odd product the cyclic
   window starts at lane n; lanes beyond n are discarded by the store. #}
{% macro mul(odd=false, slot=0, first=false, extra='') %}
    MULT.RC.VE {{ ('LR9' if odd else 'LR8') if slot else ('LR10' if odd else 'LR0') }} {{ 'LR6' if odd else 'LR4' }} 0 LR0 {{ cr.dstail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; {{ extra }} ;;
{% endmacro %}
{% macro pipe(slot, first=false, branch='') %}
    {{ mul(false, slot, first, 'LD.MULT.CYCLIC LR5 ' ~ cr.in1 ~ ' ' ~ ('LR0' if slot else 'LR8') ~ ' ; SET LR11 LR5 ;') }}
    {{ mul(true, slot, false, 'LD.MULT R0 LR11 ' ~ cr.in0 ~ ' ; INC LR5 1 ; ' ~ branch) }}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR7 CR0 ; SET LR8 CR0 ; SET LR9 {{ cr.n }} ;;
    DEC LR7 1 ;;
    INC LR8 128 ; INC LR9 128 ; SET LR10 {{ cr.n }} ;;
head:
    ADD LR2 LR1 {{ cr.pairs }} ; SET LR4 CR0 ; SET LR6 {{ cr.m }} ;;
    DEC LR2 1 ;;
row:
    SET LR5 LR1 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR1 {{ cr.in1 }} LR0 ; INC LR5 1 ; BEQ LR1 LR2 single ;;
    {{ pipe(0, true, 'BEQ LR5 LR2 last1 ;') }}
pair1:
    {{ pipe(1, false, 'BEQ LR5 LR2 last0 ;') }}
    {{ pipe(0, false, 'BLT.S LR5 LR2 pair1 ;') }}
last1:
    {{ mul(false, 1) }}
    {{ mul(true, 1, false, 'B store ;') }}
last0:
    {{ mul() }}
odd0:
    {{ mul(true) }}
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dstail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ; INC LR7 1 ; INC LR4 1 ; INC LR6 1 ; BLT.S LR4 {{ cr.mlast }} row ;;
    ADD LR1 LR1 {{ cr.pairs }} ; INC LR3 1 ; BLT.S LR3 {{ cr.blast }} head ;;
    HALT ;;
single:
    {{ mul(false, 0, true, 'B odd0 ;') }}
