{# Keep the query in R0 and pipeline the streamed key rows. #}
{% macro dot(prefetch) %}
    MULT.RC.VV LR3 R0 0 LR11 {{ cr.ds_main }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR9 {{ cr.ds_main }}.H ; INC LR9 1 ; ADD LR7 LR7 {{ cr.strides }}.H {% if prefetch %}; LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR11 ; DEC LR10 1 ; BNE LR10 CR1 column{% endif %} ;;
{% endmacro %}
{% macro output(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ; INC LR0 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR12 128 ; DEC LR0 1 ;;
group:
    SET LR3 CR0 ; SET LR4 {{ cr.heads }}.H ;;
head:
    SET LR5 {{ cr.sizes }}.L ; SET LR6 LR1 ;;
row:
    BEQ LR3 CR0 aligned ;;
    {# Rotate the entire row to preserve its quantization scale. #}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR11 ;;
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR12 ;;
    MULT.RC.VE LR3 CR1 0 LR11 {{ cr.ds_main }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds_main }}.L {{ cr.qf_in0 }}.L {{ cr.rotated }} LR11 ;;
    LD.MULT R0 LR11 {{ cr.rotated }} ; B start_row ;;
aligned:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
start_row:
    SET LR7 LR2 ; SET LR8 {{ cr.sizes }}.H ;;
tile:
    SET LR9 CR0 ; SET LR10 LR8 ; BLE.S LR8 LR12 load_key ;;
    SET LR10 LR12 ;;
load_key:
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR11 ; DEC LR9 1 ; DEC LR10 1 ; BEQ LR10 CR1 last_column ;;
column:
    {{ dot(true) }}
last_column:
    {{ dot(false) }}
    BLE.S LR8 LR12 tail ;;
    {{ output(cr.ds_main ~ '.L') }}
    DEC LR8 128 ; B tile ;;
tail:
    {{ output(cr.ds_tail ~ '.L') }}
    ADD LR6 LR6 {{ cr.strides }}.L ; DEC LR5 1 ; BNE LR5 CR1 row ;;
    ADD LR3 LR3 {{ cr.heads }}.L ;;
    BLT.S LR3 LR12 next_head ;;
    DEC LR3 128 ; INC LR1 1 ; INC LR2 1 ;;
next_head:
    DEC LR4 1 ; BNE LR4 CR1 head ;;
    ADD LR1 LR1 {{ cr.a_gap }} ; ADD LR2 LR2 {{ cr.b_gap }} ; DEC LR13 1 ; BNE LR13 CR1 group ;;
    HALT ;;
