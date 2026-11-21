{# Flat merge cursor (LR8, LR9) skips physical padding at each d3 boundary.
   Each output tile streams six weight digits for bias and each reduction lane. #}
{% macro dot(s, first=false, advance=false) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 {% if advance %}; INC LR3 1 ; DEC LR7 1{% endif %} ;;
{% for p in range(6) %}
    MULT.RC.VE {{ 'LR1' if p % 2 else 'LR0' }} {{ s }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first and p == 0 %}.FIRST{% endif %}{% if p < 5 %} ; LD.MULT.CYCLIC LR4 {{ cr.w }} {{ 'LR0' if p % 2 else 'LR1' }} ; INC LR4 1{% endif %} ;;
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
{% if bias %}
{{ dot('CR1', true) }}
{% else %}
{{ dot('CR0', true) }}
{% endif %}
load_input:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
lane:
{{ dot('LR3', false, true) }}
    BEQ LR3 {{ cr.last_lane }} next_input ;;
    BNE LR7 CR0 lane ;;
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
