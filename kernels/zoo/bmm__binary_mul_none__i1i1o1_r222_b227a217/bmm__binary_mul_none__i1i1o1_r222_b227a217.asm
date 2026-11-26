    SET LR0 {{ cr.out_prev }} ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 {{ cr.s0_b }} ; SET LR4 {{ cr.s0_m }} ; SET LR15 CR0 ;;
row:
    SET LR10 LR2 ; SET LR6 {{ cr.s0_n }} ; SET LR8 {{ cr.out_prev }} ;;
{% macro dot(first, more, loop=false) %}
    MULT.RC.VV LR15 R0 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR8 {{ cr.ds }}.L ; INC LR10 1{% if first %} ; INC.MODP2 LR8 CR1 7{% endif %}{% if more %} ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR15{% if loop %} ; B reduce{% endif %}{% else %} ; DEC LR6 1 ; BEQ LR6 CR1 tail{% endif %} ;;
{% endmacro %}
column:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR15 ; SET LR9 LR1 ; SET LR11 {{ cr.chunks }} ;;
    LD.MULT R0 LR10 {{ cr.in1 }} ; DEC LR11 1 ; BEQ LR11 CR1 single ;;
    {{ dot(true, true) }}
reduce:
    LD.MULT R0 LR10 {{ cr.in1 }} ; DEC LR11 1 ; BEQ LR11 CR1 last ;;
    {{ dot(false, true, true) }}
single:
    {{ dot(true, false) }}
    B column_done ;;
last:
    {{ dot(false, false) }}
column_done:
    BNE LR8 LR13 column ;;
{% macro store(half, control) %}
    SET LR12 CR0 ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.{{ half }} {{ cr.qf_in0 }}.L {{ cr.tmp }} LR12 ;;
    LD.MULT R0 LR12 {{ cr.tmp }} ;;
    LD.MULT.CYCLIC LR12 {{ cr.factor }} LR15 ;;
    MULT.RC.VV LR15 R0 0 LR15 {{ cr.ds }}.{{ half }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR0 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ; {{ control }} ;;
{% endmacro %}
    {{ store('L', 'B column') }}
tail:
    {{ store('H', 'ADD LR1 LR1 ' ~ cr.chunks ~ ' ; DEC LR4 1 ; BNE LR4 CR1 row') }}
    ADD LR2 LR2 {{ cr.rhs_batch }} ; DEC LR3 1 ; SET LR4 {{ cr.s0_m }} ; BNE LR3 CR1 row ;;
    HALT ;;
