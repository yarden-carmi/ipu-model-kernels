{# Rotate a full query row so that its head begins at lane zero, without
   narrowing the data used to select the scratch row's scale. #}
{% macro rotate(row, scratch, reg) %}
    LD.MULT.CYCLIC {{ row }} {{ cr.in0 }} LR0 ;;
    LD.MULT.CYCLIC {{ row }} {{ cr.in0 }} LR12 ;;
    MULT.RC.VE LR3 CR1 0 LR0 {{ cr.widths }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.widths }}.L {{ cr.qf_in0 }}.L {{ cr.rotated }} {{ scratch }} ;;
    LD.MULT {{ reg }} {{ scratch }} {{ cr.rotated }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR7 CR0 ; SET LR12 CR0 ; SET LR14 CR0 ;;
    INC LR12 128 ; INC LR14 1 ;;
group:
    SET LR3 CR0 ; SET LR4 {{ cr.heads }}.H ;;
head:
    SET LR5 LR1 ; SET LR6 {{ cr.sizes }}.L ;;
pair:
    ADD LR15 LR5 {{ cr.strides }}.L ; BEQ LR3 CR0 aligned ;;
    {{ rotate('LR5', 'LR0', 'R0') }}
    {{ rotate('LR15', 'LR14', 'R1') }}
    B columns ;;
aligned:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    LD.MULT R1 LR15 {{ cr.in0 }} ;;
columns:
    SET LR8 LR2 ; SET LR9 CR0 ; SET LR10 {{ cr.sizes }}.H ;;
    DEC LR9 1 ; DEC LR10 1 ; SET LR11 {{ cr.sizes }}.H ;;
column:
    LD.MULT.CYCLIC LR8 {{ cr.in1 }} LR0 ;;
    MULT.RC.VV LR3 R0 0 LR0 {{ cr.widths }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR9 {{ cr.widths }}.H ; INC LR9 1 ;;
    MULT.RC.VV LR3 R1 0 LR0 {{ cr.widths }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR10 {{ cr.widths }}.H ; INC LR10 1 ; ADD LR8 LR8 {{ cr.strides }}.H ; DEC LR11 1 ; BNE LR11 CR1 column ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.out_width }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; ADD LR5 LR15 {{ cr.strides }}.L ; DEC LR6 2 ;;
    BNE LR6 CR0 pair ;;
    ADD LR3 LR3 {{ cr.heads }}.L ;;
    BLT.S LR3 LR12 next_head ;;
    DEC LR3 128 ; INC LR1 1 ; INC LR2 1 ;;
next_head:
    DEC LR4 1 ; BNE LR4 CR1 head ;;
    ADD LR1 LR1 {{ cr.a_gap }} ; ADD LR2 LR2 {{ cr.b_gap }} ; DEC LR13 1 ; BNE LR13 CR1 group ;;
    HALT ;;
