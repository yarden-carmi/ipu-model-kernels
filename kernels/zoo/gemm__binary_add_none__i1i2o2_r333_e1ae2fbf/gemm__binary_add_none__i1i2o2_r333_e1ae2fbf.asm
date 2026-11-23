{% set q = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% macro weight(slot) -%}
LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1
{%- endmacro %}
{% macro dot(src, bias=false) %}
{% for p in range(3) %}
    MULT.RC.VE {{ 'LR3' if p == 1 else 'LR0' }} {{ src }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if bias and p == 0 %}.FIRST{% endif %}{% if p < 2 %} ; {{ weight('LR3' if p == 0 else 'LR0') }}{% endif %}{% if not bias and p == 2 %} ; BNE LR7 CR0 feature{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR3 {{ cr.slot }} ; SET LR5 CR0 ;;
    SET LR11 CR0 ; SET LR13 CR0 ; SET LR8 LR15 ;;
position:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR11 ; SET LR7 LR12 ; {{ weight('LR0') }} ;;
    {{ dot('CR1', true) }}
feature:
    LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR7 1 ;;
    {{ weight('LR0') }} ; ADD LR2 LR2 {{ cr.blocks }} ;;
    {{ dot('LR13') }}
    LD.MULT R0 LR5 {{ cr.in1 }} ; DEC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ cr.qf_in1 }}.L ; ACC.ADD ; BEQ LR6 CR0 last_tile ;;
    {{ store(cr.full) }}
    B tile ;;
last_tile:
    {{ store(cr.tail) }}
    DEC LR14 1 ; DEC LR8 1 ; INC LR13 1 ;;
    BEQ LR14 CR0 finish ;;
    BEQ LR8 CR0 next_batch ;;
    INC.MODP2 LR13 CR0 7 ;;
    BNE LR13 CR0 position ;;
    INC LR11 1 ; B position ;;
next_batch:
    SUB LR11 LR2 {{ cr.blocks }} ;;
    INC LR11 1 ; SET LR13 CR0 ; SET LR8 LR15 ; B position ;;
finish:
    HALT ;;
