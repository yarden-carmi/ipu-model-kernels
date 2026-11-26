{% macro store(mask) %}
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

// The view enumerates the stored tensor's row-major offsets in order.
// Walk its stored (a,b,c) coordinates, where c is the fastest counter.
// LR6 is the packed lane, LR7 the row block, and LR8 the physical row.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR12 CR0 ; SET LR15 CR0 ;;
    INC LR15 128 ;;
row:
    SET LR9 LR15 ; SET LR10 CR0 ;;
{% if (out0_d0 * out0_d1) % 128 != 0 %}
    BNE LR2 {{ cr.last_chunk }} begin ;;
    SET LR9 LR13 ;;
begin:
{% endif %}
    DEC LR10 1 ; DEC LR9 1 ;;
gather:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    MULT.EE LR6 CR1 0 LR0 {{ cr.tail }}.H {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR10 {{ cr.tail }}.H ; INC LR10 1 ; INC LR5 1 ; ADD LR8 LR8 {{ cr.source_width }} ;;
    BNE LR5 {{ cr.in0_d2 }} advance ;;
    SET LR5 CR0 ; INC LR4 1 ; ADD LR6 LR6 {{ cr.in0_d0 }} ;;
    BEQ LR4 {{ cr.in0_d1 }} next_batch ;;
normalize:
    BLT.S LR6 LR15 reset_row ;;
    DEC LR6 128 ; INC LR7 1 ; B normalize ;;
next_batch:
    INC LR3 1 ; SET LR4 CR0 ; SET LR7 CR0 ;;
    SET LR6 LR3 ; B normalize ;;
reset_row:
    SET LR8 LR7 ;;
advance:
    BLT.S LR10 LR9 gather ;;
    LD.MULT R0 LR1 {{ cr.in1 }} ;;
{% if (out0_d0 * out0_d1) % 128 != 0 %}
    BEQ LR2 {{ cr.last_chunk }} tail ;;
{% endif %}
    {{ store('CR15.L') }}
    INC LR2 1 ; B next_row ;;
{% if (out0_d0 * out0_d1) % 128 != 0 %}
tail:
    {{ store(cr.tail ~ '.L') }}
    SET LR2 CR0 ;;
{% endif %}
next_row:
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
