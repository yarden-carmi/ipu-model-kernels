{% macro gather32() %}
{% for row in range(32) %}
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    MULT.VE LR6 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADD LR8 LR8 {{ cr.ic }} ; ADDBI LRD2 1 ;;
{% endfor %}
{% endmacro %}

{% macro gather64() %}
    {{ gather32() }}
    {{ gather32() }}
    INC LR9 64 ;;
{% endmacro %}

{% macro add_store(ds) %}
    LD.MULT R0 LR10 {{ cr.operand }} ;;
    MULT.VE LR4 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ;;
    INC LR10 1 ; INC LR11 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR15 CR0 ;;
batch:
    SET LR13 {{ cr.in0_d1 }} ;;
plane:
    SET LR6 CR0 ; SET LR7 LR5 ; SET LR10 CR0 ;;
    SET LR11 LR15 ; SET LR12 CR0 ;;
column:
    SET LR8 LR7 ; SET LR9 CR0 ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ;;
    {{ gather64() }}
    BEQ LR9 {{ cr.in0_d2 }} half_chunk ;;
    {{ gather64() }}
    {{ add_store(cr.full) }}
    BLT.S LR9 {{ cr.in0_d2 }} chunk ;;
    B column_done ;;
half_chunk:
    {{ add_store(cr.half) }}
column_done:
    ADD LR11 LR11 {{ cr.skip }} ; INC LR12 1 ; INC LR6 1 ;;
    INC.MODP2 LR6 CR0 7 ;;
    BEQ LR12 {{ cr.in0_d3 }} plane_done ;;
    BNE LR6 CR0 column ;;
    INC LR7 1 ; B column ;;
plane_done:
    SUB LR8 LR8 LR7 ; ADD LR15 LR15 {{ cr.oc }} ; DEC LR13 1 ;;
    ADD LR5 LR5 LR8 ; BNE LR13 CR0 plane ;;
    SUB LR15 LR11 {{ cr.skip }} ; DEC LR14 1 ;;
    BNE LR14 CR0 batch ;;
    HALT ;;
