{# Copy each head to a panel, rotating its 64 lanes down before dot products. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
group:
    SET LR4 {{ cr.heads }} ; SET LR5 LR1 ; SET LR6 LR2 ;;
    SET LR7 CR0 ;;
head:
    SET LR8 LR5 ; SET LR9 CR0 ; SET LR10 {{ cr.counts }}.L ;;
{% macro copy(tag, base, stride, count, qf) %}
    LD.MULT R0 LR8 {{ base }} ; DEC LR10 1 ;;
    ADD LR8 LR8 {{ stride }} ;;
{{ tag }}:
    MULT.VE LR7 CR1 0 LR0 {{ cr.widths }}.L {{ qf }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR8 {{ base }} ; DEC LR10 1 ;;
    ACTIVATE.QUANTIZE identity {{ cr.widths }}.L {{ qf }}.L {{ cr.panel }} LR9 ; ADD LR8 LR8 {{ stride }} ;;
    INC LR9 1 ; BGT.S LR10 CR0 {{ tag }} ;;
    MULT.VE LR7 CR1 0 LR0 {{ cr.widths }}.L {{ qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.widths }}.L {{ qf }}.L {{ cr.panel }} LR9 ;;
    INC LR9 1 ;;
{% endmacro %}
    {{ copy('copy_a', cr.in0, cr.strides ~ '.L', cr.counts ~ '.L', cr.qf_in0) }}
    SET LR8 LR6 ; SET LR10 {{ cr.counts }}.H ;;
    {{ copy('copy_b', cr.in1, cr.strides ~ '.H', cr.counts ~ '.H', cr.qf_in1) }}
    SET LR8 CR0 ; SET LR10 {{ cr.counts }}.L ;;
pair:
    SET LR9 {{ cr.counts }}.L ; SET LR11 CR0 ; SET LR12 {{ cr.counts }}.H ;;
    DEC LR11 1 ; DEC LR12 1 ; LD.MULT.CYCLIC LR8 {{ cr.panel }} LR0 ;;
    INC LR8 1 ; SET LR14 CR0 ;;
    INC LR14 128 ;;
    LD.MULT.CYCLIC LR8 {{ cr.panel }} LR14 ;;
    INC LR8 1 ; LD.MULT R0 LR9 {{ cr.panel }} ;;
columns:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.widths }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.widths }}.L ; INC LR11 1 ; INC LR9 1 ;;
    MULT.RC.VV LR14 R0 0 LR0 {{ cr.widths }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR12 {{ cr.widths }}.L ; INC LR12 1 ; LD.MULT R0 LR9 {{ cr.panel }} ; BLT.S LR11 {{ cr.col_limit }} columns ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.widths }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.widths }}.L ; INC LR11 1 ;;
    MULT.RC.VV LR14 R0 0 LR0 {{ cr.widths }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR12 {{ cr.widths }}.L ; INC LR12 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.widths }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; DEC LR10 2 ;;
    INC LR3 1 ;;
    BGT.S LR10 CR0 pair ;;
    DEC LR4 1 ; BEQ LR7 CR0 upper ;;
    SET LR7 CR0 ; INC LR5 1 ; INC LR6 1 ; B head_next ;;
upper:
    INC LR7 64 ;;
head_next:
    BGT.S LR4 CR0 head ;;
    ADD LR1 LR1 {{ cr.group_a }} ; ADD LR2 LR2 {{ cr.group_b }} ; DEC LR15 1 ; BGT.S LR15 CR1 group ;;
    HALT ;;
