{% macro mac(first) %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR8 1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ; INC LR6 1 ;;
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.widths }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; INC LR7 1 ; BEQ LR8 CR0 reduced ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR11 CR0 ;;
    SET LR12 CR0 ; SET LR13 {{ cr.out0_d0 }} ;;
group:
    SET LR3 LR11 ; SET LR4 LR12 ; SET LR14 {{ cr.heads_unit }}.L ;;
head:
    SET LR9 CR0 ;;
pair:
    INC LR9 1 ; SET LR10 CR0 ;;
query:
    SET LR6 LR3 ; SET LR7 LR4 ; SET LR8 {{ cr.k }} ;;
    {{ mac(true) }}
reduce:
    {{ mac(false) }}
    B reduce ;;
reduced:
    BNE LR10 CR0 merge ;;
    ACTIVATE.QUANTIZE identity {{ cr.widths }}.L {{ cr.qf_out0 }}.L {{ cr.merge }} LR0 ; DEC LR9 1 ; SET LR10 CR1 ; B query ;;
merge:
    LD.MULT.CYCLIC LR0 {{ cr.merge }} LR0 ; SET LR5 LR15 ; SET LR1 CR0 ;;
    DEC LR5 1 ; DEC LR1 1 ; SET LR8 LR15 ;;
copy:
    INC LR1 1 ; INC LR5 1 ; DEC LR8 1 ; MULT.RC.VE LR1 CR1 0 LR0 {{ cr.heads_unit }}.H {{ cr.qf_out0 }}.L ; AGG.SUM.FIRST LR5 {{ cr.heads_unit }}.H ; BNE LR8 CR1 copy ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.widths }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR9 2 ;;
    BLT.S LR9 {{ cr.m }} pair ;;
    SET LR3 LR6 ; SET LR4 LR7 ; DEC LR14 1 ; BNE LR14 CR1 head ;;
    ADD LR11 LR11 {{ cr.apitch }} ; ADD LR12 LR12 {{ cr.bpitch }} ; DEC LR13 1 ; BNE LR13 CR1 group ;;
    HALT ;;
