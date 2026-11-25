{% set scale = 'CR1' if format == 'fp32' else cr.inv %}
{% macro accumulate(op) -%}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 {{ scale }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; {{ op }} LR0 {{ cr.active }}.L ; INC LR1 1 ; INC LR3 1 ;;
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
channel:
{% if format == 'fp32' %}
    MULT.VE LR0 CR0 0 LR0 {{ cr.scalar }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR3 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR7 CR0 ;;
    INC LR7 32 ;;
fp_row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    SET LR4 CR0 ; INC LR1 1 ; INC LR3 1 ;;
fp_lane:
    BLT.S LR6 LR10 fp_add ;;
    INC.MODP2 LR5 CR0 3 ;;
    BLT.S LR6 LR11 fp_add ;;
    SET LR5 LR7 ;;
fp_add:
    MULT.EE LR4 CR1 0 LR0 {{ cr.scalar }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 {{ cr.scalar }}.L ;;
    INC LR4 1 ; INC.MODP2 LR5 CR1 5 ; INC LR6 1 ;;
    INC.MODP2 LR8 CR1 9 ;;
    BNE LR8 CR0 fp_continue ;;
    ACTIVATE.QUANTIZE identity {{ cr.vec }}.L {{ cr.qf_out0 }}.L {{ cr.sum_row }} LR9 ;;
    INC LR9 1 ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.scalar }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
fp_continue:
    BLT.S LR4 {{ cr.lanes }} fp_lane ;;
    BLT.S LR3 {{ cr.spatial_rows }} fp_row ;;
    ACTIVATE.QUANTIZE identity {{ cr.vec }}.L {{ cr.qf_out0 }}.L {{ cr.sum_row }} LR9 ;;
    LD.MULT R0 LR0 {{ cr.sum_row }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.vec }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
    SET LR8 CR0 ;;
fp_merge:
    BEQ LR8 LR9 fp_merged ;;
    INC LR8 1 ;;
    LD.MULT R0 LR8 {{ cr.sum_row }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.vec }}.L {{ cr.qf_out0 }}.L ; ACC.ADD ; B fp_merge ;;
fp_merged:
    ACTIVATE.QUANTIZE identity {{ cr.vec }}.L {{ cr.qf_out0 }}.L {{ cr.sum_row }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.sum_row }} ; SET LR4 CR0 ;;
    MULT.EE LR7 CR1 0 LR0 {{ cr.scalar }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
fp_fold:
    SET LR5 LR4 ; SET LR6 LR4 ;;
    INC LR6 1 ;;
    MULT.EE LR5 CR1 0 LR0 {{ cr.scalar }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR6 {{ cr.scalar }}.L ;;
{% for i in range(3) %}
    INC LR5 8 ;;
    MULT.EE LR5 CR1 0 LR0 {{ cr.scalar }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ cr.scalar }}.L ;;
{% endfor %}
    INC LR4 1 ;;
    BLT.S LR4 LR13 fp_fold ;;
    ACTIVATE.QUANTIZE identity {{ cr.fold_ds }}.L {{ cr.qf_out0 }}.L {{ cr.sum_row }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.sum_row }} ; SET LR4 CR0 ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.scalar }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
    INC LR4 1 ;;
fp_horizontal:
    MULT.EE LR4 CR1 0 LR0 {{ cr.scalar }}.L {{ cr.qf_out0 }}.L ; ACC.ADD ;;
    INC LR4 1 ;;
    BLT.S LR4 LR12 fp_horizontal ;;
{% else %}
    SET LR3 CR0 ;;
    {{ accumulate('AGG.SUM.FIRST') }}
    BEQ LR3 {{ cr.spatial_rows }} store ;;
spatial:
    {{ accumulate('AGG.SUM') }}
    BLT.S LR3 {{ cr.spatial_rows }} spatial ;;
{% endif %}
store:
{% if format == 'fp32' %}
    ACTIVATE.QUANTIZE identity {{ cr.scalar }}.L {{ cr.qf_out0 }}.L {{ cr.sum_row }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.sum_row }} ;;
    MULT.VE LR0 {{ cr.inv_fp32 }} 0 LR0 {{ cr.scalar }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.scalar }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.out0_d1 }} channel ;;
    HALT ;;
