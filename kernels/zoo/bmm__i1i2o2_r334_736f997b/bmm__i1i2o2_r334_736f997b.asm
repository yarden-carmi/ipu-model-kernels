{# Query rows occupy the lanes. Broadcast the corresponding key scalar. #}
{% macro mac(first) %}
    MULT.RC.VE LR15 LR11 0 LR15 {{ cr.ds_main }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro output(half) %}
    INC LR2 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_main }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR13 CR0 ; SET LR15 CR0 ; DEC LR2 1 ;;
    INC LR13 128 ;;
group:
    SET LR3 CR0 ; SET LR4 {{ cr.heads }}.H ;;
head:
    SET LR5 {{ cr.sizes }}.H ; SET LR6 LR1 ;;
column:
    SET LR7 {{ cr.sizes }}.L ; SET LR8 LR0 ;;
tile:
    SET LR9 LR8 ; SET LR10 LR6 ; SET LR11 LR3 ;;
    SET LR12 {{ cr.heads }}.L ; LD.MULT R0 LR10 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR15 ;;
    {{ mac(true) }}
next_k:
    DEC LR12 1 ; BEQ LR12 CR1 result ;;
    INC.MODP2 LR11 CR1 7 ; ADD LR9 LR9 {{ cr.strides }}.L ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR15 ;;
    BNE LR11 CR0 reduce ;;
    INC LR10 1 ; LD.MULT R0 LR10 {{ cr.in1 }} ;;
reduce:
    {{ mac(false) }}
    B next_k ;;
result:
    BGT.S LR7 LR13 full ;;
    {{ output('H') }}
    ADD LR6 LR6 {{ cr.strides }}.H ; DEC LR5 1 ; BNE LR5 CR1 column ;;
    ADD LR0 LR0 {{ cr.a_head }} ; ADD LR3 LR3 {{ cr.heads }}.L ;;
wrap:
    BLT.S LR3 LR13 next_head ;;
    DEC LR3 128 ; INC LR1 1 ; B wrap ;;
next_head:
    DEC LR4 1 ; BNE LR4 CR1 head ;;
    ADD LR0 LR0 {{ cr.a_gap }} ; ADD LR1 LR1 {{ cr.b_gap }} ; DEC LR14 1 ; BNE LR14 CR1 group ;;
    HALT ;;
full:
    {{ output('L') }}
    DEC LR7 128 ; INC LR8 1 ; B tile ;;
