{# A retains its channel-major rows. Each RHS row gives all keys for
   one reduction index, so the output never leaves the accumulator. #}
{% macro product(first) %}
    MULT.RC.VE {{ 'LR14' if first else 'LR15' }} LR9 0 LR15 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }}
{%- endmacro %}
{% macro output() %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; INC LR6 1
{%- endmacro %}
    DEC LR6 1 ; INC LR14 128 ;;
group:
    SET LR1 {{ cr.out0_d1 }} ; SET LR2 CR0 ; SET LR3 CR0 ;;
head:
    ADD LR4 LR10 LR2 ; SET LR5 {{ cr.m }} ; ADD LR11 LR3 {{ cr.k }} ; LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR14 ;;
    DEC LR11 3 ;;
row:
    SET LR8 LR7 ; SET LR9 LR3 ; LD.MULT R0 LR4 {{ cr.in0 }} ; BEQ {{ cr.k }} CR1 single ;;
    {{ product(true) }} ; LD.MULT.CYCLIC LR8 {{ cr.in1 }} LR15 ; INC LR8 1 ; DEC LR5 1 ; BGT.S LR9 LR11 last ;;
reduce:
    {{ product(false) }} ; LD.MULT.CYCLIC LR8 {{ cr.in1 }} LR15 ; INC LR8 1 ; INC LR9 1 ; BLT.S LR9 LR11 reduce ;;
last:
    {{ product(false) }} ; INC LR9 1 ; {{ output() }} ; ADD LR4 LR4 {{ cr.a_stride }} ; BGT.S LR5 CR0 row ;;
    B advance ;;
single:
    {{ product(true) }} ; {{ output() }} ; ADD LR4 LR4 {{ cr.a_stride }} ; DEC LR5 1 ; BGT.S LR5 CR1 row ;;
advance:
    ADD LR7 LR7 {{ cr.k }} ; ADD LR3 LR3 {{ cr.k }} ; DEC LR1 1 ;;
    INC.MODP2 LR3 CR0 7 ;;
    BNE LR3 CR0 head_tail ;;
    INC LR2 1 ;;
head_tail:
    BGT.S LR1 CR0 head ;;
    ADD LR10 LR10 {{ cr.a_group }} ; ADD LR7 LR7 {{ cr.b_gap }} ; DEC LR0 1 ; BGT.S LR0 CR1 group ;;
    HALT ;;
