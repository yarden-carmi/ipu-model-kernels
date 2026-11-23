{# Coefficients stream in output-tile order. Input rows advance by one channel plane. #}
{% macro coeff_load(slot) -%}
LD.MULT.CYCLIC LR8 {{ cr.coeff }} {{ slot }} ; INC LR8 1
{%- endmacro %}
{% macro mac(slot, src, op='ACC.ADD') -%}
MULT.RC.VE {{ slot }} {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    INC LR1 128 ; SET LR4 CR0 ; SET LR11 {{ cr.in0_d0 }} ;;
    DEC LR3 1 ;;
batch:
    SET LR10 {{ cr.in0_d2 }} ; SET LR12 CR0 ; SET LR14 CR0 ;;
height:
    ADD LR5 LR4 LR14 ; SET LR9 {{ cr.in0_d3 }} ;;
pixel:
    SET LR8 CR0 ; SET LR6 LR15 ;;
    DEC LR8 1 ;;
tile:
    SET LR2 LR5 ; SET LR7 {{ cr.k }} ; {{ coeff_load('LR0') }} ;;
    {{ mac('LR0', 'CR1', 'ACC.ADD.FIRST') }} ; {{ coeff_load('LR0') }} ;;
    {{ mac('LR0', 'CR1') }} ;;
channel:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ coeff_load('LR0') }} ;;
    {{ mac('LR0', 'LR12') }} ; {{ coeff_load('LR0') }} ; ADD LR2 LR2 {{ cr.pitch }} ; DEC LR7 1 ;;
    {{ mac('LR0', 'LR12') }} ; BNE LR7 CR0 channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; DEC LR6 1 ;;
    BNE LR6 CR0 tile ;;
    ADD LR5 LR5 {{ cr.hchunks }} ; DEC LR9 1 ;;
    BNE LR9 CR0 pixel ;;
    DEC LR10 1 ; INC LR12 1 ;;
    BEQ LR10 CR0 batch_end ;;
    BNE LR12 LR1 height ;;
    SET LR12 CR0 ; INC LR14 1 ; B height ;;
batch_end:
    ADD LR4 LR4 {{ cr.batch_pitch }} ; DEC LR11 1 ;;
    BNE LR11 CR0 batch ;;
    HALT ;;
