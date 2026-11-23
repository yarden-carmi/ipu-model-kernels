{% macro mac(src, first=false) %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR1 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR6 CR0 ; SET LR12 {{ cr.m }} ;;
    SET LR13 {{ cr.in0_d1 }} ; DEC LR1 1 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
    INC LR2 1 ;;
{% endfor %}
matrix_row:
    SET LR4 {{ cr.O }} ; SET LR5 CR0 ;;
    DEC LR5 1 ;;
output_block:
    SET LR7 LR3 ; SET LR10 LR6 ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ;;
    SET LR11 {{ cr.k }} ; {{ mac('CR1', true) }} ;;

{# LR7/LR10 are the current memory row/lane. Stream up to the
   physical row boundary or the end of this dot product. #}
segment:
    ADD LR8 LR10 LR11 ; LD.MULT R0 LR7 {{ cr.in0 }} ;;
    BLT.S LR8 {{ cr.width }} segment_end_ready ;;
    SET LR8 {{ cr.width }} ;;
segment_end_ready:
    SUB LR11 LR11 LR8 ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ;;
    ADD LR11 LR11 LR10 ; DEC LR10 1 ; DEC LR8 2 ;;
tap:
    {{ mac('LR10') }} ; INC LR10 1 ; BLT.S LR10 LR8 prefetch ;;
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.width }} block_done ;;
    INC LR7 1 ; SET LR10 CR0 ; BNE LR11 CR0 segment ;;
block_done:
    DEC LR4 1 ; BNE LR4 CR1 store_full ;;
    {{ store(cr.tail) }}
    SET LR3 LR7 ; SET LR6 LR10 ; DEC LR12 1 ;;
    DEC LR13 1 ; BNE LR13 CR1 next_row ;;
    SET LR13 {{ cr.in0_d1 }} ; BEQ LR6 CR0 next_row ;;
    INC LR3 1 ; SET LR6 CR0 ;;
next_row:
    BNE LR12 CR0 matrix_row ;;
    HALT ;;
store_full:
    {{ store(cr.full) }}
    B output_block ;;
prefetch:
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ; B tap ;;
