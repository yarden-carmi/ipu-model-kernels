{% macro store(mask) %}
    LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

// Traverse the view in (a,c,b) order, matching in1 and out0.
// LR4: padded storage-row base, LR5: column within that stored row.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR14 CR0 ;;
    SET LR13 CR0 ;;
    INC LR13 128 ;;
batch:
    SET LR4 CR0 ; SET LR5 LR14 ; SET LR15 {{ cr.out0_d2 }} ;;
column:
    SET LR12 {{ cr.out0_d1 }} ;;
chunk:
    SET LR11 LR12 ; BGE.S LR13 LR12 tail_chunk ;;
    SET LR11 LR13 ; DEC LR12 128 ; B start_gather ;;
tail_chunk:
    SET LR12 CR0 ;;
start_gather:
    SET LR2 CR0 ; DEC LR11 2 ;;
    DEC LR2 1 ;;
normalize:
    BLT.S LR5 {{ cr.in0_d2 }} locate ;;
    SUB LR5 LR5 {{ cr.in0_d2 }} ; ADD LR4 LR4 {{ cr.width }} ; B normalize ;;
locate:
    SET LR6 LR4 ; SET LR7 LR5 ;;
row_block:
    BLT.S LR7 LR13 load ;;
    INC LR6 1 ; DEC LR7 128 ; B row_block ;;
load:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR7 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.scalar }}.L ; ADD LR5 LR5 {{ cr.step }} ; INC LR2 1 ; BNE LR2 LR11 normalize ;;
    BEQ LR12 CR0 end_column ;;
    {{ store('CR15.L') }}
    B chunk ;;
end_column:
    {{ store(cr.tail ~ '.L') }}
    DEC LR15 1 ; BNE LR15 CR1 column ;;
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.step }} batch ;;
    HALT ;;
