{# Keep a flat cursor through the merge view, skipping each physical row's padding. #}
{% macro dot(s, first=false) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 {% if not first %}; INC LR3 1 ; DEC LR7 1{% endif %} ;;
{% for p in range(4) %}
    MULT.RC.VE {{ 'LR1' if p % 2 else 'LR0' }} {{ s }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first and p == 0 %}.FIRST{% endif %}{% if p < 3 %} ; LD.MULT.CYCLIC LR4 {{ cr.w }} {{ 'LR0' if p % 2 else 'LR1' }} ; INC LR4 1{% elif not first %} ; BNE LR3 LR11 lane{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.slot }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR10 {{ cr.rows }} ;;
    DEC LR9 1 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR3 LR9 ; SET LR7 {{ cr.k }} ;;
    {{ dot('CR1' if bias else 'CR0', true) }}
load_input:
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR11 LR3 LR7 ;;
    BLT.S LR11 {{ cr.last_lane }} lane ;;
    SET LR11 {{ cr.last_lane }} ;;
lane:
    {{ dot('LR3') }}
    BEQ LR3 {{ cr.last_lane }} next_input ;;
    B store_tile ;;
next_input:
    INC LR2 1 ; SET LR3 CR0 ;;
    DEC LR3 1 ; BNE LR7 CR0 load_input ;;
store_tile:
    DEC LR6 1 ;;
    BEQ LR6 CR0 last_tile ;;
    {{ store(cr.full) }}
    INC LR5 1 ; B tile ;;
last_tile:
    {{ store(cr.tail) }}
    INC LR5 1 ; SET LR8 LR2 ; SET LR9 LR3 ;;
    DEC LR10 1 ;;
    BNE LR10 CR0 row ;;
    HALT ;;
