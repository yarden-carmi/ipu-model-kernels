{% macro scatter() %}
    MULT.RC.VE LR0 LR4 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD8 LRD10 LR14 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    SET LR12 CR0 ;;
spatial:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
group:
    SET LR6 CR0 ; SET LR13 CR0 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 CR0 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
channel:
    BNE LR4 CR0 scale_ready ;;
    LD.MULT R0 LR3 {{ cr.in1 }} ;;
    INC LR3 1 ;;
scale_ready:
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
    SET LR8 {{ cr.indices_lo }} ; SET LR9 {{ cr.indices_hi }} ; INC LR5 1 ;;
    SET LR10 {{ cr.indices_lo }} ;;
    SET LR11 {{ cr.indices_hi }} ; SET LR7 CR0 ; SET LR14 CR0 ;;
    ADDB LRD10 LR13 ;;
{% for i in range(6) %}
    BEQ LR7 {{ cr.chunks }} last_chunk ;;
    {{ scatter() }}
    ADDBI LRD8 8 ; ADDBI LRD10 8 ; INC LR7 1 ;;
{% endfor %}
last_chunk:
    ADDB LRD8 {{ cr.mask_pair }}.L ; ADDB LRD10 {{ cr.mask_pair }}.L ; SET LR14 {{ cr.mask_pair }}.H ;;
    {{ scatter() }}
    INC LR2 1 ; INC LR6 1 ; ADD LR13 LR13 {{ cr.dim_pair }}.H ;;
    INC.MODP2 LR4 CR1 7 ;;
    BEQ LR2 {{ cr.inner }} store_last ;;
    BLT.S LR6 {{ cr.pack }} channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; B group ;;
store_last:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.last_valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; INC LR12 1 ;;
    BLT.S LR12 {{ cr.dim_pair }}.L spatial ;;
    HALT ;;
