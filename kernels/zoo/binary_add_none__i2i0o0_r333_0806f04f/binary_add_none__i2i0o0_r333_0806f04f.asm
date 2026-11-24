// Stream the view in (d2,d1,d0) order, with d0 consecutive in in0.
// in1 and out0 use the same padded d0 rows in (d1,d2) order.
{% set aligned = (in0_d1 * in0_d2) % 128 == 0 %}
{% macro store() %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    INC LR7 128 ;;
{% if not aligned %}
    SET LR10 {{ cr.slab }} ;;
{% endif %}
column:
    SET LR1 LR5 ; SET LR2 {{ cr.out0_d1 }} ;;
pixel:
{% if aligned %}
    LD.MULT R0 LR3 {{ cr.in0 }} ; ADD LR6 LR4 {{ cr.out0_d0 }} ; ADD LR8 LR3 CR1 ;;
{% if 128 % out0_d0 != 0 %}
    BGE.S LR7 LR6 add ;;
    LD.MULT R1 LR8 {{ cr.in0 }} ;;
{% endif %}
add:
    MULT.VE LR4 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    {{ store() }}
    SET LR4 LR6 ; BLT.S LR6 LR7 next ;;
    SUB LR4 LR6 LR7 ; SET LR3 LR8 ;;
next:
{% else %}
    // A batch slab can end mid-vector; gather one lane at a time and skip its padding.
    SET LR11 CR0 ;;
gather:
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.scalar }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.scalar }}.L ;;
    INC LR11 1 ; INC LR4 1 ; DEC LR10 1 ;;
    BEQ LR10 CR0 slab_end ;;
    BLT.S LR4 LR7 gathered ;;
    SET LR4 CR0 ; INC LR3 1 ; B gathered ;;
slab_end:
    SET LR4 CR0 ; INC LR3 1 ; SET LR10 {{ cr.slab }} ;;
gathered:
    BLT.S LR11 {{ cr.out0_d0 }} gather ;;
    LD.MULT R0 LR1 {{ cr.in1 }} ;;
    {{ store() }}
{% endif %}
    ADD LR1 LR1 {{ cr.out0_d2 }} ; DEC LR2 1 ;;
    BNE LR2 CR0 pixel ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.out0_d2 }} column ;;
    HALT ;;
