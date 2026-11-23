{# A's feature axis is contiguous. Keep its current K segment in R0
   while streaming B's output-lane vectors through cyclic slot zero. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR1 128 ; SET LR5 CR0 ; SET LR6 CR0 ;;
group:
    SET LR3 LR2 ; SET LR4 CR0 ; SET LR7 {{ cr.heads }} ;;
head:
    SET LR8 LR3 ; SET LR9 {{ cr.m }} ;;
row:
    SET LR10 LR5 ; SET LR11 {{ cr.k }} ; SET LR12 LR4 ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.dsout }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR13 LR8 ;;
segment:
    SUB LR14 LR1 LR12 ; LD.MULT R0 LR13 {{ cr.in0 }} ;;
    BLE.S LR14 LR11 segment_ready ;;
    SET LR14 LR11 ;;
segment_ready:
    SUB LR11 LR11 LR14 ; DEC LR12 1 ; INC LR13 1 ;;
    LD.MULT.CYCLIC LR10 {{ cr.in1 }} LR0 ; DEC LR14 1 ; BEQ LR14 CR1 drain ;;
{% macro product() %}
    MULT.RC.VE LR0 LR12 0 LR0 {{ cr.dsout }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; INC LR12 1 ; ADD LR10 LR10 CR1
{%- endmacro %}
stream:
    {{ product() }} ; LD.MULT.CYCLIC LR10 {{ cr.in1 }} LR0 ; DEC LR14 1 ; BGT.S LR14 CR1 stream ;;
drain:
    {{ product() }} ; BNE LR11 CR0 next_segment ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsout }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; DEC LR9 1 ; ADD LR8 LR8 {{ cr.achunks }} ;;
    INC LR6 1 ; BNE LR9 CR0 row ;;
    SET LR5 LR10 ; DEC LR7 1 ; ADD LR4 LR4 {{ cr.k }} ;;
    BEQ LR5 {{ cr.bend }} done ;;
    BEQ LR7 CR0 next_group ;;
normalize:
    BLT.S LR4 LR1 head ;;
    DEC LR4 128 ; INC LR3 1 ; B normalize ;;
next_group:
    ADD LR2 LR2 {{ cr.agroup }} ; B group ;;
next_segment:
    SET LR12 CR0 ; B segment ;;
done:
    HALT ;;
