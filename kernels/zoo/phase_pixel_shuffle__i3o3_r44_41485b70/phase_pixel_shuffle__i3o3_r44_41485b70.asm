{# Copy each input phase row to interleaved output lanes. #}
{% macro phase(a, b) %}
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    SET LR2 {{ cr.dst_lo }} ; SET LR3 {{ cr.dst_hi }} ;;
    {% if b %}ADDBI LRD2 {{ b }} ;;{% endif %}
    {% for chunk in range((in0_d3 + 7) // 8) %}
    MULT.VE LR8 CR1 0 LR9 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 {{ 8 - [8, in0_d3 - chunk * 8] | min }} ;;
    {% if not loop.last %}INC LR8 8 ; ADDBI LRD2 {{ 8 * s }} ;;{% endif %}
    {% endfor %}
    SET LR8 CR0 ; ADD LR11 LR11 {{ cr.phase_step }} ;;
{% endmacro %}
    SET LR0 {{ cr.src_lo }} ; SET LR1 {{ cr.src_hi }} ;;
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR9 CR0 ; SET LR12 CR0 ;;
channel_loop:
    SET LR7 CR0 ; SET LR10 LR12 ;;
batch_loop:
    SET LR13 CR0 ;;
y_loop:
    SET LR11 LR10 ; SET LR8 CR0 ;;
    {% for a in range(s) %}
      {% for b in range(s) %}{{ phase(a,b) }}{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
    {% endfor %}
    INC LR10 1 ; INC LR13 1 ;;
    BLT.S LR13 LR14 y_loop ;;
    INC LR7 1 ;;
    BLT.S LR7 {{ cr.in0_d0 }} batch_loop ;;
    ADD LR12 LR12 {{ cr.channel_step }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.channels }} channel_loop ;;
    HALT ;;
