{% macro store(mask) %}
    LD.MULT R0 LR1 {{ cr.in1 }} ; SET LR2 CR0 ; SET LR3 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR14 CR0 ;;
    SET LR13 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR13 128 ;;
batch:
    SET LR4 CR0 ; SET LR5 LR14 ; SET LR15 {{ cr.dims }}.H ;;
// The row starts at flat storage offset a + A*b; c advances by A*B.
origin:
    BLT.S LR5 {{ cr.span }}.L row ;;
    SUB LR5 LR5 {{ cr.span }}.L ; ADD LR4 LR4 {{ cr.span }}.H ; B origin ;;
row:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR12 {{ cr.out0_d2 }} ;;
chunk:
    BGE.S LR13 LR12 tail_chunk ; SET LR11 LR12 ;;
    SET LR11 LR13 ; DEC LR12 128 ; B start_gather ;;
tail_chunk:
    SET LR12 CR0 ;;
start_gather:
// AGG sees the incremented destination; the branch sees the old cursor.
    DEC LR2 1 ; DEC LR11 2 ;;
gather:
    BLT.S LR7 {{ cr.span }}.L locate ;;
    SUB LR7 LR7 {{ cr.span }}.L ; ADD LR6 LR6 {{ cr.span }}.H ;;
locate:
{% if in0_d2 <= 128 %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ;;
{% elif in0_d2 <= 256 %}
    BLT.S LR7 LR13 low ; ADD LR10 LR6 CR1 ;;
    LD.MULT R0 LR10 {{ cr.in0 }} ; SUB LR9 LR7 LR13 ; B loaded ;;
low:
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ;;
loaded:
{% else %}
    SET LR10 LR6 ; SET LR9 LR7 ;;
physical_chunk:
    BLT.S LR9 LR13 load ;;
    INC LR10 1 ; DEC LR9 128 ; B physical_chunk ;;
load:
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% endif %}
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.scalar }}.L ;
    ADD LR6 LR6 {{ cr.step_row }} ; ADD LR7 LR7 {{ cr.step_lane }} ; INC LR2 1 ; BNE LR2 LR11 gather ;;
    BEQ LR12 CR0 end_row ;;
    {{ store('CR15.L') }}
    B chunk ;;
end_row:
    {{ store(cr.tail ~ '.L') }}
    DEC LR15 1 ; ADD LR5 LR5 {{ cr.dims }}.L ;;
    BNE LR15 CR0 origin ;;
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.dims }}.L batch ;;
    HALT ;;
