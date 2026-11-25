{% set full = cr.full ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% macro chunk(count, label) %}
    LD.MULT R0 LR5 {{ cr.coeff }} ; SET LR6 CR0 ; SET LR7 CR0 ;;
    LD.MULT.CYCLIC LR4 {{ cr.panel }} LR0 ; INC LR5 1 ; DEC LR6 1 {% if count > 3 %}; INC LR7 {{ count - 3 }}{% elif count == 2 %}; DEC LR7 1{% endif %} ;;
{% if count > 1 %}
{{ label }}:
    MULT.RC.VE LR0 LR6 0 LR0 {{ full }} {{ iq }} ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.panel }} LR0 ; INC LR4 1 ; INC LR6 1 ; BLT.S LR6 LR7 {{ label }} ;;
{% endif %}
    MULT.RC.VE LR0 LR6 0 LR0 {{ full }} {{ iq }} ; ACC.ADD ; INC LR6 1 ; INC LR4 1 ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR9 CR0 ;;
    SET LR13 CR0 ; SET LR14 {{ cr.in0_d0 }} ; SET LR15 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
    INC LR1 1 ;;
{% endfor %}
batch:
    SET LR3 CR0 ; SET LR12 {{ cr.blocks }} ;;
panel_block:
    SET LR1 LR13 ; SET LR4 CR0 ; SET LR8 {{ cr.k }} ;;
    SET LR7 CR0 ;;
    {% if in0_d1 % 128 %}
    INC LR7 {{ in0_d1 % 128 }} ; BEQ LR12 CR1 panel_feature ;;
    SET LR7 CR0 ;;
    {% endif %}
    INC LR7 64 ;;
    INC LR7 64 ;;
panel_feature:
    SET LR2 LR1 ; SET LR10 CR0 ; SET LR11 CR0 ;;
    SET LR6 LR7 ;;
    MULT.EE LR0 CR0 0 LR0 {{ full }} {{ iq }} ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
panel_lane:
    MULT.EE LR4 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD14 LRD10 7 ;;
    ADD LR2 LR2 {{ cr.pitch }} ; ADDBI LRD10 1 ; DEC LR6 1 ; BEQ LR6 CR1 panel_store ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ; B panel_lane ;;
panel_store:
    ACTIVATE.QUANTIZE identity {{ full }} {{ iq }} {{ cr.panel }} LR3 ;;
    INC LR3 1 ; DEC LR8 1 ; INC.MODP2 LR4 CR1 7 ; BEQ LR8 CR1 panel_next ;;
    BNE LR4 CR0 panel_feature ;;
    INC LR1 1 ; B panel_feature ;;
panel_next:
    SUB LR13 LR2 {{ cr.pitch }} ;;
    INC LR13 1 ; DEC LR12 1 ; BNE LR12 CR1 panel_block ;;

    SET LR2 CR0 ; SET LR10 {{ cr.n }} ;;
channel:
    SET LR11 CR0 ; SET LR12 {{ cr.blocks }} ;;
block:
    LD.MULT R0 LR2 {{ cr.coeff }} ; SET LR5 LR2 ; SET LR4 LR11 ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.ADD.FIRST ; INC LR5 1 ;;
{% if k > 128 %}
    SET LR8 CR0 ;;
    INC LR8 {{ (k - 1) // 128 }} ;;
groups:
    {{ chunk(128, 'reduce_full') }}
    DEC LR8 1 ; BNE LR8 CR1 groups ;;
{% endif %}
    {{ chunk((k - 1) % 128 + 1, 'reduce_last') }}
    DEC LR12 1 ; ADD LR11 LR11 {{ cr.k }} ; BNE LR12 CR1 full_block ;;
    {{ store(cr.tail) }}
    SET LR2 LR5 ; DEC LR10 1 ; BNE LR10 CR1 channel ;;
    DEC LR14 1 ; BNE LR14 CR1 batch ;;
    HALT ;;
full_block:
    {{ store(cr.full) }}
    B block ;;
