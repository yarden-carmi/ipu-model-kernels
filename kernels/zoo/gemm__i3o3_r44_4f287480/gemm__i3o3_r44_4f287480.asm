{# Each accumulator lane computes a different spatial position. #}
{% macro mac(index) %}
    MULT.RC.VE LR0 {{ index }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{% endmacro %}
{% macro seed(op) %}
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ op }}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR7 CR0 ;;
    SET LR8 {{ cr.n }} ; SET LR13 CR0 ; SET LR14 CR0 ;;
    INC LR13 127 ; INC LR14 128 ;;
channel:
    SET LR15 CR0 ; SET LR10 {{ cr.out0_d0 }} ;;
batch:
    SET LR11 {{ cr.tiles }} ; SET LR9 LR15 ;;
tile:
    SET LR4 LR7 ; SET LR5 LR9 ; SET LR6 {{ cr.k }} ;;
    LD.MULT R0 LR4 {{ cr.coeff }} ;;
    {{ seed('ADD.FIRST') }} ; LD.MULT R0 LR4 {{ cr.coeff }} ; INC LR4 1 ;;
    {{ seed('ADD') }} ; INC LR4 1 ;;
block:
    LD.MULT R0 LR4 {{ cr.coeff }} ; SET LR3 CR0 ; SET LR12 LR14 ;;
    LD.MULT R1 LR4 {{ cr.coeff }} ; INC LR4 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; INC LR4 1 ;;
tap:
    {{ mac('LR3') }} ;;
    {{ mac('LR12') }} ; INC LR3 1 ; DEC LR6 1 ; ADD LR5 LR5 {{ cr.stride }} ; BEQ LR6 CR1 finish ;;
    BLT.S LR13 LR3 block ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; INC LR12 1 ; B tap ;;
finish:
    DEC LR11 1 ; BEQ LR11 CR1 last_tile ;;
    {{ store(cr.full) }} ;;
    INC LR2 1 ; INC LR9 1 ; B tile ;;
last_tile:
    {{ store(cr.tail) }} ;;
    INC LR2 1 ; ADD LR15 LR15 {{ cr.batch_step }} ; DEC LR10 1 ; BNE LR10 CR1 batch ;;
    SET LR7 LR4 ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    HALT ;;
