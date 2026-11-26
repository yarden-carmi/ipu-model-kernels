// Gather the strided first view and the contiguous second view into the
// packed output lanes. LR4 is the flat index of batch zero at channel LR2.
{% macro element() %}
    SET LR7 LR5 ;;
    ADD LR8 LR6 LR6 ;;
    BLT.S LR7 LR15 first_half ;;
    DEC LR7 128 ; INC LR8 1 ;;
first_half:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    MULT.EE LR7 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.ds_pair }}.L ;;
    LD.MULT R0 LR9 {{ cr.in1 }} ;;
    MULT.EE LR10 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR11 {{ cr.ds_pair }}.L ;;
    INC LR11 1 ; INC LR5 1 ; ADD LR9 LR9 {{ cr.batchstep }} ;;
    BLT.S LR5 {{ cr.cols }} element_done ;;
    SUB LR5 LR5 {{ cr.cols }} ; INC LR6 1 ;;
element_done:
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR13 CR0 ; SET LR15 CR0 ;;
    INC LR15 128 ;;
pixel:
    SET LR2 CR0 ; SET LR5 LR13 ; SET LR12 CR0 ;;
    SET LR6 CR0 ;;
divide:
    BLT.S LR5 {{ cr.cols }} divided ;;
    SUB LR5 LR5 {{ cr.cols }} ; INC LR6 1 ; B divide ;;
divided:
    SET LR10 LR1 ;;
    BLT.S LR10 LR15 group ;;
    DEC LR10 128 ; INC LR12 1 ;;
group:
    SET LR11 CR0 ;;
channel:
    ADD LR9 LR2 LR2 ; SET LR14 CR0 ;;
    ADD LR9 LR9 LR12 ;;
    INC LR14 4 ;;
batch:
    {{ element() }}
    DEC LR14 1 ;;
    BNE LR14 CR0 batch ;;
    INC LR2 1 ;;
    BEQ LR2 {{ cr.channels }} last ;;
    BLT.S LR11 LR15 channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; B group ;;
last:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% if out0_d1 % 64 > 0 and out0_d1 % 64 <= 32 %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endif %}
    BEQ LR3 {{ cr.rows }} done ;;
    INC LR1 1 ; ADD LR13 LR13 {{ cr.step }} ; B pixel ;;
done:
    HALT ;;
