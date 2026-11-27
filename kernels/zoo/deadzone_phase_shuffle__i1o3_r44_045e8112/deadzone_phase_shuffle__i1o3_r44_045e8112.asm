{% set gain = cr.gain_f32 if format == 'fp32' else cr.gain_nx %}
{% set threshold = cr.threshold_f32 if format == 'fp32' else cr.threshold_nx %}
{% set sixth = cr.sixth_f32 if format == 'fp32' else cr.sixth_nx %}
{% macro row(phase, slot, tag) %}
    SET LR1 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR7 LR5 ; ADD LR8 LR5 {{ lr.rowstep }} ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    INC LR4 {{ phase }} ;;
gather_{{ tag }}:
    LD.MULT R0 LR7 {{ cr.in0 }} ;;
    MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADD LR3 LR3 {{ lr.byte }} ; INC LR4 1 ;;
    MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    DEC LR4 1 ; ADD LR3 LR3 {{ lr.byte }} ; ADD LR7 LR7 {{ cr.chunks }} ;;
    BLT.S LR7 LR8 gather_{{ tag }} ;;
    DEC LR4 {{ phase }} ;;
    SET LR7 CR0 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.temp }} LR7 ;;
    LD.MULT R0 LR7 {{ cr.temp }} ;;
    MULT.VE LR0 {{ gain }} 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ;;
    MULT.VE LR0 {{ gain }} 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.MAX ;;
    SET LR7 CR1 ;;
    INC LR7 2 ;;
    LD.MULT R0 LR7 {{ cr.temp }} ;;
    MULT.VE LR0 {{ threshold }} 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
    SET LR7 CR1 ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf_in0 }}.L {{ cr.temp }} LR7 ;;
    LD.MULT R0 LR7 {{ cr.temp }} ;;
    MULT.VE LR0 {{ sixth }} 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    INC LR7 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.temp }} LR7 ;;
    LD.MULT R0 LR7 {{ cr.temp }} ;;
    SET LR7 CR0 ;;
    LD.MULT.CYCLIC LR7 {{ cr.temp }} LR0 ;;
    SET LR7 CR0 ;;
    INC LR7 {{ slot }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.temp }} LR7 ;;
{% endmacro %}
{% macro pack(slot) %}
    SET LR7 CR0 ; SET LR8 CR0 ;;
    INC LR7 {{ slot }} ;;
    SET LR1 CR0 ; SET LR0 CR0 ;;
    LD.MULT R0 LR7 {{ cr.temp }} ;;
pack_{{ slot }}:
    MULT.EE LR8 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADD LR1 LR1 {{ lr.byte }} ; ADD LR3 LR3 {{ lr.byte }} ; INC LR8 1 ;;
    BLT.S LR8 {{ cr.width }} pack_{{ slot }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR10 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR7 CR1 ;;
    INC LR7 2 ;;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf_in0 }}.L {{ cr.temp }} LR7 ;;
channel:
    SET LR9 CR0 ;;
height:
{{ row(0, 4, 'a') }}
{{ row(2, 5, 'b') }}
    ADD LR5 LR5 {{ lr.rowstep }} ; INC LR9 1 ;;
{{ row(0, 6, 'c') }}
{{ row(2, 7, 'd') }}
    ADD LR5 LR5 {{ lr.rowstep }} ; INC LR9 1 ;;
    SET LR2 CR0 ; SET LR3 CR0 ;;
{{ pack(4) }}
{{ pack(5) }}
{{ pack(6) }}
{{ pack(7) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ;;
    BLT.S LR9 {{ lr.height }} height ;;
    SUB LR5 LR5 {{ lr.rowstep }} ;;
    SET LR9 CR1 ;;
rewind:
    SUB LR5 LR5 {{ lr.rowstep }} ; INC LR9 1 ;;
    BLT.S LR9 {{ lr.height }} rewind ;;
    INC LR4 4 ; INC LR10 1 ;;
    BLT.S LR4 {{ lr.limit }} no_wrap ;;
    SET LR4 CR0 ; INC LR5 1 ;;
no_wrap:
    BLT.S LR10 {{ lr.total_channels }} channel ;;
    HALT ;;
