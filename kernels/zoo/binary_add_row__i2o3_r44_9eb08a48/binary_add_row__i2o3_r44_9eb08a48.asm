{% macro add_store(ds) %}
    LD.MULT R0 LR10 {{ cr.operand }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; INC LR10 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ;;
    INC LR11 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 {{ cr.planes }} ; SET LR11 CR0 ; SET LR14 CR0 ;;
    INC LR14 128 ;;
plane:
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR10 CR0 ;;
row:
    ADD LR9 LR4 LR8 ; SET LR12 {{ cr.in0_d3 }} ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR13 CR0 ;;
gather:
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    MULT.EE LR6 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR9 LR9 {{ cr.ic }} ;;
    ADDBI LRD2 1 ; DEC LR12 1 ; INC LR13 1 ;;
    BEQ LR12 CR0 tail ;;
    BLT.S LR13 LR14 gather ;;
    {{ add_store('CR15.L') }}
    B chunk ;;
tail:
    {{ add_store(cr.tail ~ '.L') }}
    INC LR7 1 ; INC LR6 1 ;;
    BEQ LR7 {{ cr.in0_d2 }} next_plane ;;
    BLT.S LR6 LR14 row ;;
    SET LR6 CR0 ; INC LR8 1 ; B row ;;
next_plane:
    ADD LR4 LR4 {{ cr.plane_rows }} ; DEC LR5 1 ;;
    BNE LR5 CR0 plane ;;
    HALT ;;
