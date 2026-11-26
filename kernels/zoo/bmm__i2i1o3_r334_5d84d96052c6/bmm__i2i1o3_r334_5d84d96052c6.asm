{# Each key-channel row holds a vector of output columns. #}
{% macro product(first=false) %}
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR11 ;;
    MULT.RC.VE LR11 LR9 0 LR11 {{ cr.ds_main }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
    INC LR9 1 ; ADD LR7 LR7 {{ cr.strides }}.H ; DEC LR10 1 ;;
{% endmacro %}
{% macro output(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR12 128 ;;
group:
    SET LR3 CR0 ; SET LR4 {{ cr.heads }}.H ;;
head:
    SET LR5 {{ cr.sizes }}.L ; SET LR6 LR1 ;;
row:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    SET LR8 {{ cr.sizes }}.H ; SET LR14 LR2 ;;
tile:
    SET LR7 LR14 ; SET LR9 LR3 ; SET LR10 {{ cr.heads }}.L ;;
    {{ product(true) }}
    BEQ LR10 CR0 store ;;
channel:
    {{ product() }}
    BNE LR10 CR0 channel ;;
store:
    BLE.S LR8 LR12 tail ;;
    {{ output(cr.ds_main ~ '.L') }}
    DEC LR8 128 ; INC LR14 1 ; B tile ;;
tail:
    {{ output(cr.ds_tail ~ '.L') }}
    ADD LR6 LR6 {{ cr.strides }}.L ; DEC LR5 1 ; BNE LR5 CR1 row ;;
    ADD LR2 LR2 {{ cr.key_head }} ; ADD LR3 LR3 {{ cr.heads }}.L ;;
    BLT.S LR3 LR12 next_head ;;
    DEC LR3 128 ; INC LR1 1 ;;
next_head:
    DEC LR4 1 ; BNE LR4 CR1 head ;;
    ADD LR1 LR1 {{ cr.a_gap }} ; ADD LR2 LR2 {{ cr.b_gap }} ; DEC LR13 1 ; BNE LR13 CR1 group ;;
    HALT ;;
