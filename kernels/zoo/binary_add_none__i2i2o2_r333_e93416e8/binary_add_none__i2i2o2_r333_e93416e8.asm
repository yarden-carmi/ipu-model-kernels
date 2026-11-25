{% macro store(mask) %}
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
// Input storage offset for logical (a,j,k) is a + d0*j + d0*d1*k.
// Keep its quotient (scaled by physical row width) and remainder separately.
batch:
    SET LR4 CR0 ; SET LR5 LR14 ; SET LR15 CR0 ;;
normalize_start:
    BLT.S LR5 {{ cr.input_span }}.L row ;;
    SUB LR5 LR5 {{ cr.input_span }}.L ; ADD LR4 LR4 {{ cr.input_span }}.H ; B normalize_start ;;
row:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR12 {{ cr.chunks }}.L ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR10 {{ cr.chunks }}.H ;;
    BNE LR12 CR1 gather ;;
    SET LR10 {{ cr.tail }}.H ;;
gather:
    // Normalize only on carry. LR6 stays the base of the logical input row.
    BLT.S LR7 {{ cr.input_span }}.L locate ;;
    SUB LR7 LR7 {{ cr.input_span }}.L ; ADD LR6 LR6 {{ cr.input_span }}.H ;;
locate:
{% if in0_d2 <= 128 %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ;;
{% elif in0_d2 <= 256 %}
    BLT.S LR7 {{ cr.chunks }}.H low ; ADD LR8 LR6 CR1 ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ; SUB LR9 LR7 {{ cr.chunks }}.H ; B loaded ;;
low:
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ;;
loaded:
{% else %}
    SET LR8 LR6 ; SET LR9 LR7 ;;
physical_chunk:
    BLT.S LR9 {{ cr.chunks }}.H load ;;
    INC LR8 1 ; DEC LR9 128 ; B physical_chunk ;;
load:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
{% endif %}
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD2 0 ;
    ADD LR6 LR6 {{ cr.row_step }} ; ADD LR7 LR7 {{ cr.col_step }} ; DEC LR10 1 ;;
    BNE LR10 CR0 gather ; ADDBI LRD2 1 ;;
add:
    LD.MULT R0 LR1 {{ cr.in1 }} ; BNE LR12 CR1 full ;;
    {{ store(cr.tail ~ '.L') }}
    INC LR1 1 ; INC LR15 1 ; ADD LR5 LR5 {{ cr.dimensions }}.L ;;
    BLT.S LR15 {{ cr.dimensions }}.H normalize_start ;;
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.dimensions }}.L batch ;;
    HALT ;;
full:
    {{ store('CR15.L') }}
    INC LR1 1 ; DEC LR12 1 ; B chunk ;;
