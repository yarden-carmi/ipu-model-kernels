{% macro load_next() %}LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.spatial }}{% endmacro %}
{% macro mac() %}MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 {{ cr.n }} ;;
    SET LR8 CR0 ;;
channel:
    SET LR9 {{ cr.spatial }} ; SET LR10 CR0 ;;
pixel:
    SET LR4 LR8 ; SET LR3 CR0 ; SET LR11 CR0 ;;
    MULT.EE LR3 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
plane:
    SUB LR2 LR10 {{ cr.spatial }} ; SET LR3 CR0 ;;
    LD.MULT R0 LR4 {{ cr.w }} ;;
    INC LR4 1 ;;
{% if bias %}
    MULT.EE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% endif %}
{% if k >= 128 %}
    SET LR12 {{ cr.chunks }} ;;
chunk:
    LD.MULT R0 LR4 {{ cr.w }} ; SET LR3 CR0 ;;
    INC LR4 1 ; DEC LR3 1 ;;
    {{ load_next() }} ;;
lane:
    {{ mac() }} ; {{ load_next() }} ; BLT.S LR3 {{ cr.limit }} lane ;;
    {{ mac() }} ; DEC LR12 1 ;;
    BNE LR12 CR0 chunk ;;
{% endif %}
{% if k % 128 %}
    LD.MULT R0 LR4 {{ cr.w }} ; SET LR3 CR0 ;;
    INC LR4 1 ; DEC LR3 1 ;;
    {{ load_next() }} ;;
{% for group in range(4) %}
{% for i in range(32) %}
{% if group * 32 + i < k % 128 - 1 %}
    {{ mac() }} ; {{ load_next() }} ;;
{% endif %}
{% endfor %}
{% endfor %}
    {{ mac() }} ;;
{% endif %}
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.plane_count }} plane ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; INC LR10 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 pixel ;;
    ADD LR8 LR8 {{ cr.wrows }} ; DEC LR6 1 ;;
    BNE LR6 CR0 channel ;;
    HALT ;;
