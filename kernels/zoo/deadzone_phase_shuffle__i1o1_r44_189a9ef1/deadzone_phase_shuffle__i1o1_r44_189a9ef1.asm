{% set gain = cr.gain_f32 if format == 'fp32' else cr.gain_nx %}
{% set threshold = cr.threshold_f32 if format == 'fp32' else cr.threshold_nx %}
{% set sixth = cr.sixth_f32 if format == 'fp32' else cr.sixth_nx %}
{% macro phase(p) %}
    MULT.VE LR4 CR0 0 LR4 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR0 {{ lr.src0 }} ; SET LR1 {{ lr.src1 }} ;;
    ADDBI LRD0 {{ p }} ;;
    SET LR2 {{ cr.dst0 }} ; SET LR3 {{ cr.dst1 }} ;;
    SET LR10 CR0 ;;
chunk_{{ p }}:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
{% for i in range(4) %}
    MULT.VE LR4 CR1 0 LR4 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;;
{% if i < 3 %}
    ADDBI LRD0 32 ;;
    ADDBI LRD2 8 ;;
{% endif %}
{% endfor %}
    ADDBI LRD2 8 ; INC LR5 1 ; INC LR10 1 ;;
    BLT.S LR10 {{ lr.chunks }} next_{{ p }} ;;
    SET LR10 CR0 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.temp }} LR10 ;;
    LD.MULT R0 LR10 {{ cr.temp }} ;;
    MULT.VE LR4 {{ gain }} 0 LR4 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ;;
    MULT.VE LR4 {{ gain }} 0 LR4 CR15.L {{ cr.qf_in0 }}.L ; ACC.MAX ;;
    SET LR10 CR1 ;;
    INC LR10 2 ;;
    LD.MULT R0 LR10 {{ cr.temp }} ;;
    MULT.VE LR4 {{ threshold }} 0 LR4 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
    SET LR10 CR1 ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf_in0 }}.L {{ cr.temp }} LR10 ;;
    LD.MULT R0 LR10 {{ cr.temp }} ;;
    MULT.VE LR4 {{ sixth }} 0 LR4 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    INC LR10 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.temp }} LR10 ;;
    LD.MULT R0 LR10 {{ cr.temp }} ;;
    SET LR10 CR0 ;;
    LD.MULT.CYCLIC LR10 {{ cr.temp }} LR4 ;;
    MULT.RC.VV LR4 R0 0 LR4 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    SUB LR5 LR5 {{ lr.chunks }} ;;
    BEQ CR0 CR0 end_{{ p }} ;;
next_{{ p }}:
    SET LR0 {{ lr.src0 }} ; SET LR1 {{ lr.src1 }} ;;
    ADDBI LRD0 {{ p }} ;;
    BEQ CR0 CR0 chunk_{{ p }} ;;
end_{{ p }}:
{% endmacro %}
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; SET LR8 CR0 ;;
    MULT.VE LR4 CR0 0 LR4 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR10 CR1 ;;
    INC LR10 2 ;;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf_in0 }}.L {{ cr.temp }} LR10 ;;
site:
{{ phase(0) }}
    INC LR6 1 ;;
{{ phase(1) }}
    ADD LR6 LR6 {{ lr.outwidth }} ;;
    DEC LR6 1 ;;
{{ phase(2) }}
    INC LR6 1 ;;
{{ phase(3) }}
    SUB LR6 LR6 {{ lr.outwidth }} ; ADD LR5 LR5 {{ lr.chunks }} ; INC LR7 1 ;;
    INC LR6 1 ; INC LR8 1 ;;
    BLT.S LR7 {{ lr.sites }} more ;;
    HALT ;;
more:
    BLT.S LR8 {{ lr.width }} site ;;
    SET LR8 CR0 ; ADD LR6 LR6 {{ lr.outwidth }} ;;
    BEQ CR0 CR0 site ;;
