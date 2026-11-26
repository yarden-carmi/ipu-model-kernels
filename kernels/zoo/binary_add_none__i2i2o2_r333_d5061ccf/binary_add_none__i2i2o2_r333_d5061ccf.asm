{% macro flush(mask) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; SET LR2 CR0 ;;
{% endmacro %}

// LR4:LR5 is the padded row and unpadded lane of a + A*b.
// LR6:LR7 advances by A*B for each logical column.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR14 CR0 ; SET LR13 CR0 ;;
    INC LR13 128 ;;
    ADD LR8 LR13 LR13 ;;
batch:
    SET LR4 CR0 ; SET LR5 LR14 ; SET LR15 {{ cr.dims }}.H ;;
origin:
    BLT.S LR5 {{ cr.span }}.L row ;;
    SUB LR5 LR5 {{ cr.span }}.L ; ADD LR4 LR4 {{ cr.span }}.H ; B origin ;;
row:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR12 {{ cr.out0_d2 }} ;;
chunk:
    LD.MULT R1 LR3 {{ cr.in1 }} ; SET LR11 LR13 ;;
    INC LR3 1 ;;
gather:
    BLT.S LR7 {{ cr.span }}.L locate ;;
    SUB LR7 LR7 {{ cr.span }}.L ; ADD LR6 LR6 {{ cr.span }}.H ;;
locate:
{% if in0_d2 > 128 %}
    BLT.S LR7 LR13 load ; SET LR9 LR7 ; SET LR10 LR6 ;;
    INC LR10 1 ; DEC LR9 128 ;;
load:
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% else %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ;;
{% endif %}
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.scalar }}.L ;;
    MULT.EE LR11 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; AGG.SUM LR2 {{ cr.scalar }}.L ;
    ADD LR6 LR6 {{ cr.step_row }} ; ADD LR7 LR7 {{ cr.step_lane }} ; DEC LR12 1 ;;
    INC LR2 1 ; INC LR11 1 ;;
    BNE LR2 LR13 advance ;;
    {{ flush('CR15.L') }}
advance:
    BEQ LR12 CR0 end_row ;;
    // R1 indices are 128..255; the next source chunk starts at 256.
    BLT.S LR11 LR8 gather ;;
    B chunk ;;
end_row:
{% if out0_d2 <= 144 %}
    BEQ LR2 CR0 next_row ;;
    {{ flush(cr.tail ~ '.L') }}
next_row:
{% endif %}
    DEC LR15 1 ; ADD LR5 LR5 {{ cr.dims }}.L ;;
    BNE LR15 CR0 origin ;;
{% if out0_d2 > 144 %}
    BEQ LR2 CR0 next_batch ;;
    {{ flush(cr.tail ~ '.L') }}
next_batch:
{% endif %}
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.dims }}.L batch ;;
    HALT ;;
