{% macro mac() -%}
    MULT.RC.VE LR0 LR13 0 LR0 {{ cr.ds_main }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR10 LR10 {{ cr.steps }}.L ; DEC LR9 1 ; BEQ LR9 CR1 emit ;;
{%- endmacro %}
{% macro store(half) -%}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_main }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ; INC LR11 1 ;;
{%- endmacro %}

    SET LR0 CR0 ; SET LR2 {{ cr.groups }}.H ;;
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
    DEC LR11 1 ;;
group:
    SET LR3 {{ cr.groups }}.L ; SET LR6 LR4 ; SET LR7 LR5 ;;
    SET LR8 CR0 ;;
head:
    SET LR12 CR0 ;;
column:
    SET LR14 {{ cr.sizes }}.H ; SET LR15 LR6 ;;
tile:
    SET LR10 LR15 ; SET LR1 LR7 ; SET LR9 {{ cr.sizes }}.L ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.ds_main }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR1 {{ cr.in1 }} ; BNE LR8 CR0 odd ;;
even:
    {# The packed RHS row holds two reduction positions, each spanning N. #}
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ; SET LR13 LR12 ;;
    {{ mac() }}
odd:
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ; ADD LR13 LR12 {{ cr.columns }}.H ;;
    {{ mac() }}
    INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in1 }} ; B even ;;
emit:
    DEC LR14 1 ; BEQ LR14 CR1 tail ;;
    {{ store('L') }}
    INC LR15 1 ; B tile ;;
tail:
    {{ store('H') }}
    INC LR12 1 ;;
    BLT.S LR12 {{ cr.columns }}.L column ;;
    DEC LR3 1 ; BEQ LR3 CR1 next_group ;;
    ADD LR6 LR6 {{ cr.ahead }} ; ADD LR7 LR7 {{ cr.steps }}.H ; SET LR13 LR8 ;;
    INC.MODP2 LR8 {{ cr.sizes }}.L 1 ;;
    BLE.S LR13 LR8 head ;;
    INC LR7 1 ; B head ;;
next_group:
    ADD LR4 LR4 {{ cr.agroup }} ; ADD LR5 LR5 {{ cr.bgroup }} ; DEC LR2 1 ; BNE LR2 CR1 group ;;
    HALT ;;
