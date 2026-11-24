{% set k = cr.km ~ '.L' %}
{% set m = cr.km ~ '.H' %}
{% set heads = cr.nh ~ '.H' %}
{% macro dot() -%}
    MULT.RC.VV LR9 R0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.ds }}.L ; INC LR2 1
{%- endmacro %}
{% macro store(ds) -%}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR15
{%- endmacro %}

    INC LR7 128 ;;
group:
    SET LR11 LR14 ; SET LR10 LR13 ; SET LR9 {{ cr.offset }} ;;
    SET LR8 {{ cr.nh }}.H ;;
normalize:
    BLT.S LR9 LR7 head ;;
    DEC LR9 128 ; INC LR10 1 ; B normalize ;;
head:
    SET LR1 {{ cr.nh }}.L ; SET LR3 LR10 ; ADD LR6 LR9 {{ k }} ;;
column:
    LD.MULT.CYCLIC LR3 {{ cr.in1 }} LR0 ; SET LR5 LR3 ; BLE.S LR6 LR7 column_load ;;
    INC LR5 1 ;;
column_load:
    LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR7 ;;
    SET LR4 LR11 ; SET LR5 {{ m }} ;;
tile:
    SET LR2 CR0 ; SET LR6 LR5 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
    BLE.S LR5 LR7 width_ready ;;
    SET LR6 LR7 ;;
width_ready:
    SUB LR5 LR5 LR6 ; DEC LR2 1 ;;
    BEQ LR6 CR1 last ; DEC LR6 1 ;;
lane:
    {{ dot() }} ; LD.MULT R0 LR4 {{ cr.in0 }} ; ADD LR4 LR4 {{ heads }} ; DEC LR6 1 ; BNE LR6 CR1 lane ;;
last:
    {{ dot() }} ; ADD LR4 LR4 {{ heads }} ; BEQ LR5 CR0 tail ;;
    {{ store(cr.ds ~ '.H') }} ;;
    INC LR15 1 ; B tile ;;
tail:
    {{ store(cr.tail_ds ~ '.L') }} ;;
    ADD LR3 LR3 {{ cr.strides }} ; DEC LR1 1 ; INC LR15 1 ;;
    ADD LR6 LR9 {{ k }} ; BNE LR1 CR0 column ;;
    INC LR11 1 ; ADD LR9 LR9 {{ k }} ; DEC LR8 1 ;;
    BNE LR8 CR0 normalize ;;
    ADD LR14 LR14 {{ cr.a_group }} ; ADD LR13 LR13 {{ cr.b_group }} ; DEC LR12 1 ;;
    BNE LR12 CR0 group ;;
    HALT ;;
