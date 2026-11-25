{% macro store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

// Split the view's flat offset (x * Y + y) * B + b into
// a stored batch lane and an offset within that batch's Y*X plane.
    INC LR14 128 ; SET LR15 {{ cr.out0_d1 }} ;;
scanline:
    ADD LR6 LR5 LR4 ; SET LR7 CR0 ; SET LR11 {{ cr.blocks }} ;;
block:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR10 LR14 ;;
    BNE LR11 CR1 gather ;;
    SET LR10 {{ cr.tail_config }}.L ;;
gather:
    BLT.S LR6 {{ cr.plane }} load_element ;;
wrap_plane:
    SUB LR6 LR6 {{ cr.plane }} ; INC LR7 1 ;;
    BGE.S LR6 {{ cr.plane }} wrap_plane ;;
load_element:
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR10 1 ;;
    MULT.EE LR7 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD2 0 ; ADD LR6 LR6 {{ cr.plane_step }} ; BEQ LR10 CR0 add_row ;;
    ADDBI LRD2 1 ; B gather ;;
add_row:
    LD.MULT R0 LR1 {{ cr.in1 }} ; DEC LR11 1 ;;
    BEQ LR11 CR0 last_block ;;
    {{ store('CR15.L') }}
    INC LR1 1 ; B block ;;
last_block:
    {{ store(cr.tail_config ~ '.H') }}
    INC LR1 1 ;;
    ADD LR5 LR5 {{ cr.out0_d0 }} ; DEC LR15 1 ;;
    BNE LR15 CR0 scanline ;;
    SET LR5 CR0 ; INC LR4 1 ; SET LR15 {{ cr.out0_d1 }} ;;
    BLT.S LR4 {{ cr.out0_d0 }} scanline ;;
    HALT ;;
