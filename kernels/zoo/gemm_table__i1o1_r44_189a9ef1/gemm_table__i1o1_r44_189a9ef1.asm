{% macro coeff_load() %}
LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1
{% endmacro %}
{% macro mac(src, op='ACC.ADD') %}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{% endmacro %}
{% macro store(ds, extra='') %}
ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 {{ extra }}
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR2 CR0 ;;
    SET LR10 CR0 ; DEC LR3 1 ; DEC LR2 1 ;;
    DEC LR10 1 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR10 ; INC LR10 1 ;;
{% endfor %}
    SET LR10 CR0 ;;
pixel:
    INC LR2 1 ; LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR8 CR0 ; SET LR6 CR0 ; BEQ {{ cr.input_rows }} CR1 init_coeff ;;
    INC LR2 1 ; LD.MULT R1 LR2 {{ cr.in0 }} ;;
init_coeff:
    DEC LR8 1 ;;
block:
    SET LR7 CR0 ; {{ coeff_load() }} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {{ coeff_load() }} ; DEC LR7 1 ;;
    {{ mac('CR1') }} ; {{ coeff_load() }} ;;
channel:
    {{ mac('LR7') }} ; INC LR7 1 ; {{ coeff_load() }} ; BEQ LR7 {{ cr.k_last }} finish ;;
    {{ mac('LR7') }} ; {{ coeff_load() }} ; BNE CR0 CR1 channel ;;
finish:
    BLT.S LR6 {{ cr.last }} store_full ;;
    {{ mac('LR7') }} ; {{ store(cr.tail_ds, '; INC LR10 1') }} ; BLT.S LR10 {{ cr.m_last }} pixel ;;
    HALT ;;
store_full:
    {{ mac('LR7') }} ; {{ store(cr.full_ds, '; INC LR6 1') }} ; BNE CR0 CR1 block ;;
