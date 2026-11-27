{% macro output(part) %}
    SET LR4 CR0 ;;
    {% for tile in range((n + 127) // 128) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    INC LR4 1 ;;
    {% for c in range(in0_d1) %}
    SET LR2 LR8 ;;
    INC LR2 {{ part * (in0_d1 // 2) + c // 2 }} ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    SET LR3 CR0 ;;
    DEC LR3 1 ;;
    {% if c % 2 %} INC LR3 {{ in0_d3 }} ;; {% endif %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
    lane_{{ part }}_{{ tile }}_{{ c }}:
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; INC LR3 1 ; BLT.S LR3 {{ cr.end2 if c % 2 else cr.depth }} lane_{{ part }}_{{ tile }}_{{ c }} ;;
    {% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ (cr.active if tile == (n + 127) // 128 - 1 else cr.full) }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
    {% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR10 CR0 ;;
batch:
    SET LR9 CR0 ;;
pair:
    {{ output(0) }}
    {{ output(1) }}
    INC LR8 {{ in0_d1 }} ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.pairs }} pair ;;
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.batches }} batch ;;
    HALT ;;
