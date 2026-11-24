{# Align one head of B to lane zero. Its zero padding also lets a
   cyclic read place the same vector in the second packed position. #}
{% set a_stride = cr.strides ~ '.L' %}
{% set b_stride = cr.strides ~ '.H' %}
{% set k = cr.sizes ~ '.L' %}
{% set m = cr.sizes ~ '.H' %}
{% set n = cr.heads ~ '.H' %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.widths }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0
{%- endmacro %}
    INC LR8 192 ; INC LR12 128 ; SET LR5 {{ k }} ;;
    INC LR8 192 ; INC LR12 192 ;;
    INC LR12 192 ;;
    SUB LR12 LR12 {{ n }} ; MULT.VE LR0 CR0 0 LR0 {{ cr.widths }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.widths }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR5 ;;
    LD.MULT.CYCLIC LR5 {{ cr.panel }} LR8 ;;
group:
    SET LR3 {{ cr.heads }}.L ; SET LR13 {{ cr.bstart }} ;;
head:
    SET LR4 LR13 ; SET LR6 LR2 ; SET LR7 CR0 ;;
    INC LR7 128 ; SET LR5 CR0 ;;
normalize:
    BLT.S LR4 LR7 aligned ;;
    DEC LR4 128 ; INC LR6 1 ; B normalize ;;
aligned:
    ADD LR14 LR4 {{ n }} ; SET LR8 CR0 ;;
    BLE.S LR14 LR7 panel_row ;;
    SET LR8 CR1 ;;
panel_row:
    LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR9 ; ADD LR14 LR6 CR1 ;;
    BEQ LR8 CR0 panel_store ;;
    LD.MULT.CYCLIC LR14 {{ cr.in1 }} LR7 ;;
panel_store:
    MULT.RC.VE LR4 CR1 0 LR9 {{ cr.widths }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.widths }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR5 ; ADD LR6 LR6 {{ b_stride }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ k }} panel_row ;;
    SET LR10 LR1 ; SET LR11 {{ m }} ; SET LR7 CR0 ;;
pair:
    ADD LR6 LR9 CR1 ; SET LR14 LR10 ; SET LR5 CR0 ;;
    MULT.VE LR7 CR0 0 LR7 {{ cr.widths }}.H {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
reduce:
    LD.MULT R0 LR14 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.panel }} LR7 ;;
    MULT.RC.VE LR7 LR9 0 LR7 {{ cr.widths }}.H {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    MULT.RC.VE LR12 LR6 0 LR7 {{ cr.widths }}.H {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR14 LR14 {{ a_stride }} ; INC LR5 1 ;;
    BLT.S LR5 {{ k }} reduce ;;
    BEQ LR11 CR1 odd ;;
    {{ store('H') }} ; DEC LR11 2 ; B stored ;;
odd:
    {{ store('L') }} ; DEC LR11 1 ;;
stored:
    INC LR0 1 ; INC.MODP2 LR9 CR1 7 ; BEQ LR11 CR0 head_done ;;
    INC.MODP2 LR9 CR1 7 ;;
    BNE LR9 CR0 pair ;;
    INC LR10 1 ; B pair ;;
head_done:
    SET LR9 CR0 ; ADD LR1 LR1 {{ cr.ahead }} ; ADD LR13 LR13 {{ n }} ;;
    DEC LR3 1 ; BNE LR3 CR1 head ;;
    ADD LR2 LR2 {{ cr.bgroup }} ; DEC LR15 1 ; BNE LR15 CR1 group ;;
    HALT ;;
