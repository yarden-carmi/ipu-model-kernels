{% set full = cr.ds_pair ~ '.L' %}
{% macro store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ;;
{% endmacro %}
    INC LR12 128 ;;
batch:
    SET LR4 LR1 ; SET LR5 CR0 ;;
row:
    // View offset is i + d0*j + d0*d1*k. Its quotient by the
    // storage plane size is the physical lane; its remainder is the row.
    SET LR6 LR4 ; SET LR7 CR0 ; SET LR9 {{ cr.out0_d2 }} ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR10 CR0 ;;
    BGE.S LR9 LR12 normalize ; SET LR11 LR12 ;;
    SET LR11 LR9 ;;
normalize:
    BLT.S LR6 LR15 gather ;;
    SUB LR6 LR6 LR15 ; INC LR7 1 ; B normalize ;;
gather:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR7 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR6 LR6 LR14 ; INC LR10 1 ;;
    BEQ LR10 LR11 add ; ADDBI LRD2 1 ;;
    B normalize ;;
add:
    LD.MULT R0 LR8 {{ cr.in1 }} ; BEQ LR9 LR11 tail ;;
    {{ store(full) }}
    DEC LR9 128 ; B chunk ;;
tail:
    {{ store(cr.ds_pair ~ '.H') }}
    INC LR5 1 ; ADD LR4 LR4 {{ cr.out0_d0 }} ;;
    BNE LR5 {{ cr.out0_d1 }} row ;;
    INC LR1 1 ;;
    BNE LR1 {{ cr.out0_d0 }} batch ;;
    HALT ;;
