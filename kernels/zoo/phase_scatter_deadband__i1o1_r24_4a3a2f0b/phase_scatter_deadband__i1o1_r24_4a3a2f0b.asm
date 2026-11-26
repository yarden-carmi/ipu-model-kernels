{# Extract each phase with byte-indexed scatter, then write NCHW spatial rows. #}
{% macro phase(p, rowadd) %}
    SET LR0 {{ cr.src_lo }} ; SET LR1 {{ cr.src_hi }} ; SET LR2 {{ cr.dst_lo }} ;;
    SET LR3 {{ cr.dst_hi }} ; SET LR7 LR6 ; SET LR8 CR0 ;;
{% if p %}    ADDBI LRD0 {{ p }} ;;
{% endif %}
phase_{{ p }}:
    LD.MULT R0 LR7 {{ cr.in0 }} ;;
    MULT.VE LR15 CR1 0 LR15 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;;
{% for i in range(3) %}
    ADDBI LRD0 32 ; ADDBI LRD2 8 ;;
    MULT.VE LR15 CR1 0 LR15 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;;
{% endfor %}
    ADDBI LRD2 8 ; INC LR7 1 ; INC LR8 1 ;;
    SET LR0 {{ cr.src_lo }} ; SET LR1 {{ cr.src_hi }} ;;
{% if p %}    ADDBI LRD0 {{ p }} ;;
{% endif %}
    BLT.S LR8 {{ cr.chunks }} phase_{{ p }} ;;
{% if rowadd %}    ADD LR9 LR4 {{ cr.out0_d3 }} ;;
{% else %}    SET LR9 LR4 ;;
{% endif %}
{% if p % 2 %}    INC LR9 1 ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
{% endmacro %}
    SET LR15 CR0 ; SET LR6 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ;;
site:
{{ phase(0, false) }}
{{ phase(1, false) }}
{{ phase(2, true) }}
{{ phase(3, true) }}
    ADD LR6 LR6 {{ cr.chunks }} ; INC LR4 2 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.w }} next ;;
    SET LR5 CR0 ; ADD LR4 LR4 {{ cr.out0_d3 }} ;;
next:
    BLT.S LR6 {{ cr.inrows }} site ;;
    HALT ;;
