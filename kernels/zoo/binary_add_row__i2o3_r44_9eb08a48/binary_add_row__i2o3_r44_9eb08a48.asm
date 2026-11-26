{# Gather along dim 3 from the current dim-2 lane. Add the broadcast
   operand in the accumulator using its own input format. #}
{% macro tile(tag, mask) %}
    LD.MULT R1 LR13 {{ cr.operand }} ; SET LR10 CR0 ; SET LR11 LR15 ;;
    SET LR7 LR14 ;;
gather_{{ tag }}:
    LD.MULT R0 LR7 {{ cr.in0 }} ; DEC LR9 1 ;;
    MULT.EE LR5 CR1 0 LR0 {{ cr.mask }}.H {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR10 {{ cr.scalar }}.L ; ADD LR7 LR7 {{ cr.input_tiles }} ;;
    MULT.EE LR11 CR1 0 LR0 {{ cr.mask }}.H {{ cr.qf_operand }}.L ; AGG.SUM LR10 {{ cr.scalar }}.L ;;
    INC LR10 1 ; INC LR11 1 ; BNE LR9 CR0 gather_{{ tag }} ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR12 ; INC LR13 1 ;;
    INC LR12 1 ; BNE LR13 {{ cr.operand_rows }} period_{{ tag }} ;;
    SET LR13 CR0 ;;
period_{{ tag }}:
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR12 CR0 ;;
    SET LR13 CR0 ; SET LR15 CR0 ; SET LR3 {{ cr.planes }} ;;
    INC LR15 128 ;;
plane:
    SET LR6 LR1 ; SET LR5 CR0 ; SET LR4 {{ cr.out0_d2 }} ;;
row:
    SET LR14 LR6 ; SET LR8 {{ cr.count }}.H ;;
full:
    BEQ LR8 CR1 tail ;;
    SET LR9 LR15 ;;
    {{ tile('full', cr.mask ~ '.H') }}
    SET LR14 LR7 ; DEC LR8 1 ; B full ;;
tail:
    SET LR9 {{ cr.count }}.L ;;
    {{ tile('tail', cr.mask ~ '.L') }}
    DEC LR4 1 ; INC.MODP2 LR5 CR1 7 ;;
    BEQ LR4 CR0 next_plane ;;
    BNE LR5 CR0 row ;;
    INC LR6 1 ; B row ;;
next_plane:
    ADD LR1 LR1 {{ cr.plane_stride }} ; DEC LR3 1 ;;
    BNE LR3 CR0 plane ;;
    HALT ;;
