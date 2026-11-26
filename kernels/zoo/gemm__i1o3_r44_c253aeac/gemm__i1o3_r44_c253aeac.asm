{# Visit the spatial pixels of one scanline with two coefficient digits resident. #}
{% macro dots(count, label='') %}
{% for j in range(count) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.dot_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.dot_ds }}.L ; INC LR11 1 ;;
    MULT.RC.VV LR1 R0 0 LR0 {{ cr.dot_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.dot_ds }}.L ; ADD LR6 LR6 {{ cr.input_chunks }}{% if label or not loop.last %} ; LD.MULT R0 LR6 {{ cr.in0 }}{% endif %}{% if loop.last and label %} ; DEC LR13 1 ; BNE LR13 CR1 {{ label }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro pixels(count) %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SUB LR11 LR0 CR1 ;;
{% if count > 8 %}
    SET LR13 CR0 ;;
    INC LR13 {{ (count - 1) // 8 }} ;;
pixel_group:
    {{ dots(8, 'pixel_group') }}
{% endif %}
    {{ dots(1 + (count - 1) % 8) }}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR1 128 ; DEC LR2 1 ;;
    SET LR3 CR0 ; SET LR8 {{ cr.scanlines }} ;;
line:
    SET LR4 CR0 ; SET LR5 {{ cr.out0_d1 }} ;;
channel:
    LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0 ; SET LR10 LR4 ;;
    INC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR12 {{ cr.chunks }} ;;
    MULT.RC.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR7 LR3 ;;
block:
    LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR0 ; INC LR10 1 ;;
    LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR1 ; INC LR10 1 ; SET LR6 LR7 ;;
    {{ pixels(out0_d3) }}
    INC LR7 1 ; DEC LR12 1 ; BNE LR12 CR1 block ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ;;
    ADD LR4 LR4 {{ cr.coeff_stride }} ; DEC LR5 1 ; BNE LR5 CR1 channel ;;
    ADD LR3 LR3 {{ cr.input_stride }} ; DEC LR8 1 ; BNE LR8 CR1 line ;;
    HALT ;;
