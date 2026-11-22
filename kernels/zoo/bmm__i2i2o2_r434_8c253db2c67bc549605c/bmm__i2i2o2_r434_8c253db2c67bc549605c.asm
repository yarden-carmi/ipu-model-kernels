{# Each accumulator lane is one M position. B is addressed through its
   heads view: a feature-row offset and a lane, with a K-row stride. #}
{% macro mac(first) %}
    LD.MULT R0 LR9 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR13 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 {{ cr.md }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;
    ADD LR9 LR9 {{ cr.strides }}.H ; ADD LR13 LR13 {{ cr.strides }}.L ; DEC LR10 1 ;;
{% endmacro %}

{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.md }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    SET LR6 CR0 ; SET LR12 CR0 ;;
group:
    SET LR14 {{ cr.heads }}.L ; SET LR4 CR0 ;;
head:
    SET LR7 {{ cr.mn }}.H ;;
column:
    SET LR11 LR6 ; SET LR3 {{ cr.mn }}.L ;;
tile:
    SET LR13 LR11 ; SET LR9 LR5 ; SET LR10 {{ cr.k }} ;;
    {{ mac(true) }}
    BEQ LR10 CR0 finish_tile ;;
reduce:
    {{ mac(false) }}
    BNE LR10 CR0 reduce ;;
finish_tile:
    SET LR8 CR0 ;;
    INC LR8 128 ;;
    BLE.S LR3 LR8 last_tile ;;
    {{ output('L') }}
    DEC LR3 128 ; INC LR11 1 ; B tile ;;
last_tile:
    {{ output('H') }}
    INC.MODP2 LR4 CR1 7 ; DEC LR7 1 ;;
    BNE LR4 CR0 same_b_row ;;
    INC LR5 1 ;;
same_b_row:
    BNE LR7 CR0 column ;;
    ADD LR6 LR6 {{ cr.ahead }} ; DEC LR14 1 ;;
    BNE LR14 CR0 head ;;
    INC LR12 1 ; ADD LR5 LR5 {{ cr.group_jump }} ; ADD LR6 LR6 {{ cr.agroup }} ;;
    BLT.S LR12 {{ cr.heads }}.H group ;;
    HALT ;;
