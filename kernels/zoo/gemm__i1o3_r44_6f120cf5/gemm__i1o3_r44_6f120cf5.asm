{# Input rows are pixels, with consecutive K chunks per pixel.
   Each output row contains a bundle of channels, each spanning the strip width.
   Reduce directly into the packed output lane; no intermediate transpose. #}
{% macro bias_row(first) %}
    LD.MULT R0 LR4 {{ cr.coeff }} ; INC LR4 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro product() %}
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ cr.full_ds }}.L ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR1 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    DEC LR1 1 ; DEC LR2 1 ; SET LR3 {{ cr.strips }} ;;
strip:
    SET LR5 {{ cr.groups }} ; SET LR4 CR0 ;;
    DEC LR4 1 ;;
bundle:
    SET LR6 CR0 ; SET LR7 {{ cr.pack }} ;;
    BNE LR5 CR1 bias_init ;;
    SET LR7 {{ cr.tail }} ;;
bias_init:
{% for j in range(4) %}
    {{ bias_row(j == 0) }}
{% endfor %}
channel:
    SET LR8 LR2 ; SET LR9 {{ cr.out0_d3 }} ;;
pixel:
    SET LR10 LR4 ; SET LR11 {{ cr.chunks }} ;;
chunk:
    LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR8 1 ;;
{% for j in range(4) %}
    LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR0 ; INC LR10 1 ;;
    {{ product() }}
{% endfor %}
    DEC LR11 1 ;;
    BNE LR11 CR0 chunk ;;
    INC LR6 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 pixel ;;
    SET LR4 LR10 ; DEC LR7 1 ;;
    BNE LR7 CR0 channel ;;
    BEQ LR5 CR1 last_bundle ;;
    {{ store(cr.group_ds) }}
    DEC LR5 1 ; B bundle ;;
last_bundle:
    {{ store(cr.tail_ds) }}
    SET LR2 LR8 ; DEC LR3 1 ;;
    BNE LR3 CR0 strip ;;
    HALT ;;
