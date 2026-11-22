{# LR0 is zero. LR11 is the output cursor and LR12 the A head base.
   LR13 addresses the B group; LR10 is the head's offset in its feature axis. #}
{% macro output_store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ;;
    INC LR11 1 ;;
{% endmacro %}
group:
    SET LR14 {{ cr.in0_d1 }} ; SET LR10 CR0 ;;
    SET LR1 {{ cr.in0_d1 }} ;;
base_offset:
    ADD LR10 LR10 {{ cr.k }} ; DEC LR1 1 ;;
    BNE LR1 CR0 base_offset ;;
head:
    SET LR4 LR13 ; SET LR5 LR10 ;;
    SET LR7 CR0 ;;
normalize:
    INC LR7 128 ;;
normalize_test:
    BLT.S LR5 LR7 select_path ;;
    DEC LR5 128 ; INC LR4 1 ;;
    B normalize_test ;;
select_path:
    BLT.S LR7 {{ cr.n }} transpose_start ;;
    BLT.S LR7 {{ cr.k }} transpose_start ;;
    ADD LR8 LR5 {{ cr.k }} ; SET LR2 LR12 ; SET LR9 {{ cr.m }} ;;
    BLT.S LR7 LR8 dot_split_start ;;
{% macro dot(tag, split) %}
dot_{{ tag }}_start:
    SET LR3 {{ cr.n }} ;;
    DEC LR3 1 ;;
dot_{{ tag }}_row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR6 LR4 ; SET LR7 CR0 ; SET LR1 LR3 ;;
    DEC LR7 1 ;;
{% if not split %}
    LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR0 ; BEQ LR3 CR0 dot_{{ tag }}_last ;;
dot_{{ tag }}_column:
    MULT.RC.VV LR5 R0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR7 {{ cr.bconfig }}.H ; LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR0 ; ADD LR6 LR6 {{ cr.bconfig }}.L ; INC LR7 1 ; DEC LR1 1 ; BNE LR1 CR1 dot_{{ tag }}_column ;;
dot_{{ tag }}_last:
    MULT.RC.VV LR5 R0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR7 {{ cr.bconfig }}.H ; ADD LR6 LR6 {{ cr.bconfig }}.L ; INC LR7 1 ;;
{% else %}
    SET LR1 CR0 ;;
    INC LR1 128 ;;
dot_{{ tag }}_column:
    LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR0 ; ADD LR8 LR6 CR1 ;;
    LD.MULT.CYCLIC LR8 {{ cr.in1 }} LR1 ;;
    MULT.RC.VV LR5 R0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR7 {{ cr.bconfig }}.H ; ADD LR6 LR6 {{ cr.bconfig }}.L ; INC LR7 1 ;;
    BLT.S LR7 LR3 dot_{{ tag }}_column ;;
{% endif %}
    {{ output_store('H') }}
    DEC LR9 1 ;;
    BEQ LR9 CR0 dot_done ;;
    ADD LR2 LR2 {{ cr.astride }} ; B dot_{{ tag }}_row ;;
{% endmacro %}
    {{ dot('single', false) }}
    {{ dot('split', true) }}
dot_done:
    ADD LR5 LR2 CR1 ; SUB LR6 LR6 LR4 ; DEC LR14 1 ;;
    BNE LR14 CR0 head_done ;;
    ADD LR13 LR13 LR6 ; B head_done ;;
transpose_start:
    SET LR7 CR0 ;;
{# Transpose B into [column tile, reduction index, column lane]. #}
transpose_k:
    SET LR6 LR4 ; SET LR8 LR7 ;;
    SET LR9 {{ cr.n }} ;;
transpose_tile:
    SET LR3 CR0 ; SET LR1 CR0 ;;
    LD.MULT R0 LR6 {{ cr.in1 }} ;;
    MULT.EE LR5 CR0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    INC LR1 128 ;;
    BLT.S LR1 LR9 gather ;;
    SET LR1 LR9 ;;
gather:
    DEC LR1 1 ;;
    BEQ LR1 CR0 gather_last ;;
gather_next:
    MULT.EE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; LD.MULT R0 LR6 {{ cr.in1 }} ; ADD LR6 LR6 {{ cr.bconfig }}.L ; DEC LR1 1 ; BNE LR1 CR1 gather_advance ;;
    ADDBI LRD2 1 ; B gather_last ;;
gather_advance:
    ADDBI LRD2 1 ; B gather_next ;;
gather_last:
    MULT.EE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR6 LR6 {{ cr.bconfig }}.L ;;
    SET LR1 CR0 ;;
    INC LR1 128 ;;
    BLT.S LR1 LR9 panel_full ;;
{% macro panel_store(half) %}
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.{{ half }} {{ cr.qf_in1 }}.L {{ cr.panel }} LR8 ;;
{% endmacro %}
    {{ panel_store('H') }}
    INC LR7 1 ; INC LR5 1 ;;
    BGE.S LR7 {{ cr.k }} panel_done ;;
    SET LR1 CR0 ;;
    INC LR1 128 ;;
    BLT.S LR5 LR1 transpose_k ;;
    SET LR5 CR0 ; INC LR4 1 ; B transpose_k ;;
panel_full:
    {{ panel_store('L') }}
    DEC LR9 128 ; ADD LR8 LR8 {{ cr.k }} ; B transpose_tile ;;
panel_done:
    {# Final gather cursor minus its starting row equals one B group stride. #}
    SUB LR6 LR6 LR4 ;;
    DEC LR14 1 ;;
    BNE LR14 CR0 multiply ;;
    ADD LR13 LR13 LR6 ;;
multiply:
    SET LR4 {{ cr.m }} ; SET LR2 LR12 ;;
    SET LR3 CR0 ;;
    INC LR3 128 ;;
output_row:
    SET LR8 CR0 ; SET LR9 {{ cr.n }} ;;
output_tile:
    SET LR5 LR2 ; SET LR7 {{ cr.k }} ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
chunk:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR6 CR0 ;;
    INC LR5 1 ; DEC LR6 1 ; SET LR1 LR7 ;;
    BLT.S LR1 LR3 chunk_ready ;;
    SET LR1 LR3 ;;
chunk_ready:
    SUB LR7 LR7 LR1 ;;
    LD.MULT.CYCLIC LR8 {{ cr.panel }} LR0 ; DEC LR1 1 ;;
    BEQ LR1 CR0 reduce_last ;;
reduce:
    MULT.RC.VE LR0 LR6 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR8 {{ cr.panel }} LR0 ; INC LR8 1 ; INC LR6 1 ; DEC LR1 1 ; BNE LR1 CR1 reduce ;;
reduce_last:
    MULT.RC.VE LR0 LR6 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; INC LR6 1 ; INC LR8 1 ;;
    BNE LR7 CR0 chunk ;;
store:
    BLT.S LR3 LR9 output_full ;;
    {{ output_store('H') }}
    DEC LR4 1 ;;
    BEQ LR4 CR0 head_done ;;
    ADD LR2 LR2 {{ cr.astride }} ; B output_row ;;
output_full:
    {{ output_store('L') }}
    DEC LR9 128 ; B output_tile ;;
head_done:
    BEQ LR14 CR0 group_done ;;
    SUB LR5 LR5 LR2 ; ADD LR10 LR10 {{ cr.k }} ;;
    ADD LR12 LR12 LR5 ; B head ;;
group_done:
    SET LR12 LR5 ; DEC LR15 1 ;;
    BNE LR15 CR0 group ;;
    HALT ;;
