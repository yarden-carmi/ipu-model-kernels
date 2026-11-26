{% macro store(mask) %}
    LD.MULT R0 LR4 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR9 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
row:
    SET LR6 LR9 ; SET LR7 CR0 ; SET LR13 {{ cr.in0_d2 }} ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ;;
element:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR7 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADDBI LRD2 1 ; ADD LR6 LR6 {{ cr.step }} ; DEC LR13 1 ;;
    BLT.S LR6 {{ cr.plane }} no_plane_carry ;;
    SUB LR6 LR6 {{ cr.plane }} ; INC LR7 1 ;;
no_plane_carry:
    BEQ LR13 CR0 last_chunk ;;
    BLT.S LR2 CR0 full_chunk ;;
    B element ;;
full_chunk:
    {{ store(cr.full) }}
    B chunk ;;
last_chunk:
    {{ store(cr.tail) }}
    INC LR12 1 ; ADD LR9 LR9 {{ cr.in0_d0 }} ;;
    BNE LR12 {{ cr.in0_d1 }} row ;;
    INC LR11 1 ;;
    BEQ LR11 {{ cr.in0_d0 }} done ;;
    SET LR12 CR0 ; SET LR9 LR11 ; B row ;;
done:
    HALT ;;
