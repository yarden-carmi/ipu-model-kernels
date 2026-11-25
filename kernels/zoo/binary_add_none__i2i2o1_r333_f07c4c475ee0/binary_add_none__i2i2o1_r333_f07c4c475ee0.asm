{# Reduce a single broadcast element into the destination lane. This
   transposes and adds directly in FP32, without any intermediate store. #}
{% macro tile(tag, mask) %}
    SET LR10 CR0 ; SET LR9 LR12 ;;
gather_{{ tag }}:
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR9 1 ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.tail }}.H {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR10 {{ cr.scalar }}.L ; LD.MULT R0 LR7 {{ cr.in1 }} ; ADD LR6 LR6 {{ cr.pitch0 }} ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.tail }}.H {{ cr.qf_in1 }}.L ; AGG.SUM LR10 {{ cr.scalar }}.L ; ADD LR7 LR7 {{ cr.pitch1 }} ;;
    INC LR10 1 ; BNE LR9 CR0 gather_{{ tag }} ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR13 CR0 ; SET LR3 CR0 ;;
batch:
    SET LR4 CR0 ; SET LR5 {{ cr.out0_d2 }} ;;
column:
    ADD LR6 LR1 LR3 ; ADD LR7 LR2 LR3 ; SET LR12 CR0 ;;
    INC LR12 128 ; SET LR14 {{ cr.count }}.H ;;
full:
    BEQ LR14 CR1 tail ;;
    {{ tile('full', cr.tail ~ '.H') }}
    DEC LR14 1 ; B full ;;
tail:
    SET LR12 {{ cr.count }}.L ;;
    {{ tile('tail', cr.tail ~ '.L') }}
    DEC LR5 1 ; INC.MODP2 LR4 CR1 7 ;;
    BEQ LR5 CR0 next_batch ;;
    BNE LR4 CR0 column ;;
    INC LR3 1 ; B column ;;
next_batch:
    ADD LR1 LR1 {{ cr.batch }} ; ADD LR2 LR2 {{ cr.batch1 }} ; DEC LR15 1 ;;
    SET LR3 CR0 ; BNE LR15 CR0 batch ;;
    HALT ;;
