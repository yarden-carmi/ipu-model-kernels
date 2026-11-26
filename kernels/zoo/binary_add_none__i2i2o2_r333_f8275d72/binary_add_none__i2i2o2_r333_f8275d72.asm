{% macro flush(mask) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; SET LR2 CR0 ;;
{% endmacro %}

// The viewed element (a,b,c) has input storage index a + A*b + A*B*c.
// LR4:LR5 locate the spatial origin; LR6:LR7 walk its channel stride.
    INC LR13 128 ; DEC LR3 1 ;;
batch:
    SET LR4 CR0 ; SET LR5 LR14 ; SET LR15 {{ cr.dims }}.H ;;
origin:
    BLT.S LR5 {{ cr.span }}.L row ;;
    SUB LR5 LR5 {{ cr.span }}.L ; ADD LR4 LR4 {{ cr.span }}.H ; B origin ;;
row:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR12 {{ cr.outdim }}.L ;;
chunk:
    INC LR3 1 ; SET LR11 LR13 ;;
    LD.MULT R1 LR3 {{ cr.in1 }} ; ADD LR8 LR13 LR13 ;;
gather:
    SET LR9 LR7 ; SET LR10 LR6 ; BLT.S LR7 {{ cr.span }}.L locate ;;
    SUB LR7 LR7 {{ cr.span }}.L ; ADD LR6 LR6 {{ cr.span }}.H ;;
    SET LR9 LR7 ; SET LR10 LR6 ;;
locate:
{% set input_blocks = (in0_d2 + 127) // 128 %}
{% if input_blocks <= 32 %}
    {% for b in range(input_blocks - 1) %}
    LD.MULT R0 LR10 {{ cr.in0 }} ; BLT.S LR9 LR13 loaded ;;
    DEC LR9 128 ; INC LR10 1 ;;
    {% endfor %}
{% else %}
block:
    BLT.S LR9 LR13 load ;;
    DEC LR9 128 ; INC LR10 1 ; B block ;;
{% endif %}
load:
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
loaded:
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.scalar }}.L ;;
    MULT.EE LR11 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; AGG.SUM LR2 {{ cr.scalar }}.L ;
    ADD LR6 LR6 {{ cr.step_row }} ; ADD LR7 LR7 {{ cr.step_lane }} ; DEC LR12 1 ;;
    INC LR2 1 ; INC LR11 1 ; BNE LR2 {{ cr.outdim }}.H advance ;;
    {{ flush('CR15.L') }}
advance:
    BEQ LR12 CR0 end_row ;;
    BLT.S LR11 LR8 gather ;;
    B chunk ;;
end_row:
    DEC LR15 1 ; ADD LR5 LR5 {{ cr.dims }}.L ;;
    BNE LR15 CR0 origin ;;
    BEQ LR2 CR0 padding ;;
    {{ flush(cr.tail ~ '.L') }}
padding:
{% set pad_rows = ((out0_d1 + 255) // 256) * 2 * out0_d2 - (out0_d1 * out0_d2 + 127) // 128 %}
{% if pad_rows %}
    ADD LR8 LR1 {{ cr.tail }}.H ;;
pad_row:
    {{ flush(cr.scalar ~ '.H') }}
    BLT.S LR1 LR8 pad_row ;;
{% endif %}
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.dims }}.L batch ;;
    HALT ;;
