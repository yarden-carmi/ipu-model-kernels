{% macro bias(mode) %}
    LD.MULT.CYCLIC LR11 {{ cr.coeff }} LR0 ; INC LR11 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    DEC LR5 1 ; SET LR15 {{ cr.out0_d0 }} ;;
batch:
    SET LR12 LR8 ; SET LR13 {{ cr.in0_d2 }} ; SET LR10 CR0 ;;
spatial:
    SET LR9 CR0 ; SET LR6 {{ cr.n }} ;;
channel:
    SET LR11 LR9 ; SET LR4 LR12 ; SET LR14 CR0 ;;
    INC LR14 {{ chunks }} ; DEC LR11 1 ; SUB LR4 LR4 {{ cr.in_stride }} ;;
    {{ bias('ADD.FIRST') }}
    {{ bias('ADD') }}
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR3 128 ;;
{% if k % 128 %}
    BNE LR14 CR1 load_coeff ;;
    SET LR3 CR0 ;;
    INC LR3 {{ k % 128 }} ;;
load_coeff:
{% endif %}
    LD.MULT R0 LR11 {{ cr.coeff }} ; INC LR11 1 ;;
    LD.MULT R1 LR11 {{ cr.coeff }} ; INC LR11 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; ADD LR4 LR4 {{ cr.in_stride }} ; DEC LR3 1 ;;
reduce:
    MULT.RC.VE LR10 LR2 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    MULT.RC.VE LR10 LR2 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR2 128 ; BLT.S LR2 LR3 next_scalar ;;
    DEC LR14 1 ; BNE LR14 CR1 chunk ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.width_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
    ADD LR9 LR11 CR1 ; DEC LR6 1 ; BNE LR6 CR1 channel ;;
{% if in_pack == 2 %}
    BNE LR10 CR0 odd_row ;;
    INC LR10 {{ in0_d3 }} ; B row_done ;;
odd_row:
    SET LR10 CR0 ; INC LR12 1 ;;
row_done:
{% else %}
    INC LR12 1 ;;
{% endif %}
    DEC LR13 1 ; BNE LR13 CR1 spatial ;;
    ADD LR8 LR8 {{ cr.batch_stride }} ; DEC LR15 1 ; BNE LR15 CR1 batch ;;
    HALT ;;
next_scalar:
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; ADD LR4 LR4 {{ cr.in_stride }} ; DEC LR2 127 ; B reduce ;;
