{% set w = cr.w if bias else cr.w_unbiased %}
{% macro mac(src, mode='ADD') %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro bias_digit(mode) %}
    LD.MULT.CYCLIC LR7 {{ w }} LR0 ;;
    {{ mac('CR1', mode) }} ; INC LR7 1 ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1
{%- endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
    SET LR12 {{ cr.in0_d0 }} ;;
batch:
    SET LR8 {{ cr.n }} ; SET LR9 CR0 ;;
channel:
    SET LR10 LR11 ; SET LR13 {{ cr.tiles }} ;;
tile:
    SET LR7 LR9 ; SET LR6 LR10 ; SET LR14 {{ cr.groups }} ;;
{% if bias %}
    {{ bias_digit('ADD.FIRST') }}
    {{ bias_digit('ADD') }}
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
group:
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 {{ cr.last }} ;;
    INC LR2 128 ; BEQ LR14 CR1 coeff ;;
    SET LR3 CR0 ;;
    INC LR3 32 ;;
coeff:
    LD.MULT R0 LR7 {{ w }} ;;
    INC LR7 1 ; LD.MULT R1 LR7 {{ w }} ;;
    INC LR7 1 ;;
tap:
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    {{ mac('LR1') }} ; ADD LR6 LR6 {{ cr.tiles }} ;;
    {{ mac('LR2') }} ; INC LR1 1 ;;
    INC LR2 1 ; DEC LR3 1 ; BNE LR3 CR1 tap ;;
    DEC LR14 1 ; BNE LR14 CR1 group ;;
    BNE LR13 CR1 full_tile ;;
    {{ store(cr.tail) }} ; SET LR9 LR7 ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    ADD LR11 LR11 {{ cr.batch_pitch }} ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
full_tile:
    {{ store(cr.full) }} ; INC LR10 1 ; DEC LR13 1 ; B tile ;;
