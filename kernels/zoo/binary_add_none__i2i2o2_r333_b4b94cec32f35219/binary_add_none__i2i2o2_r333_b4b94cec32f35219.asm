{% set dense = (in0_d1 * in0_d2) % 128 == 0 %}
{% set lane_span = 128 if dense else in0_d2 %}
{% set paired = dense and out0_d0 * out0_d1 == 64 and out0_d2 % 2 == 0 %}
{% set stride = out0_d0 * out0_d1 % 128 %}
{% set row_step = out0_d0 * out0_d1 // 128 %}
{% set pipeline = dense and stride == 0 %}
{% macro advance_row() %}{% if row_step <= 127 %}INC LR6 {{ row_step }}{% else %}ADD LR6 LR6 {{ cr.step_row }}{% endif %}{% endmacro %}
{% macro store(mask) %}
    LD.MULT R0 LR1 {{ cr.in1 }} ; SET LR2 CR0 ; SET LR3 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
{% macro gather_lane(offset) %}
    MULT.EE {{ offset }} CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.scalar }}.L ; INC LR2 1 ;
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
{% if paired %}
// The row origin is below lane 64, so each loaded row supplies two values.
    SET LR9 LR7 ; DEC LR2 1 ; DEC LR11 3 ;;
    INC LR9 64 ;;
pair:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    {{ gather_lane('LR7') }} ;;
    {{ gather_lane('LR9') }} INC LR6 1 ; BLT.S LR2 LR11 pair ;;
{% elif pipeline %}
// The view advances by whole input rows, so the source lane stays fixed.
// Load one row ahead with each gather, except at the end of the chunk.
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR2 1 ; BEQ LR11 CR1 gather_last ;;
    DEC LR11 3 ;;
gather_next:
    {{ gather_lane('LR7') }} {{ advance_row() }} ; LD.MULT R0 LR6 {{ cr.in0 }} ; BNE LR2 LR11 gather_next ;;
gather_last:
    {{ gather_lane('LR7') }} {{ advance_row() }} ;;
{% else %}
    DEC LR2 1 ; DEC LR11 2 ;;
 gather:
{% if (out0_d0 * out0_d1) % lane_span != 0 %}
    BLT.S LR7 {{ cr.span }}.L locate ;;
    SUB LR7 LR7 {{ cr.span }}.L ; ADD LR6 LR6 {{ cr.span }}.H ;;
locate:
{% endif %}
{% if dense or in0_d2 <= 128 %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ;;
{% elif in0_d2 <= 256 %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ; ADD LR10 LR6 CR1 ; BLT.S LR7 LR13 loaded ;;
    LD.MULT R0 LR10 {{ cr.in0 }} ; SUB LR9 LR7 LR13 ;;
loaded:
{% else %}
    SET LR10 LR6 ; SET LR9 LR7 ;;
physical_chunk:
    BLT.S LR9 LR13 load ;;
    INC LR10 1 ; DEC LR9 128 ; B physical_chunk ;;
load:
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% endif %}
    {{ gather_lane('LR9') }} ADD LR6 LR6 {{ cr.step_row }} ; ADD LR7 LR7 {{ cr.step_lane }} ; BNE LR2 LR11 gather ;;
{% endif %}
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
