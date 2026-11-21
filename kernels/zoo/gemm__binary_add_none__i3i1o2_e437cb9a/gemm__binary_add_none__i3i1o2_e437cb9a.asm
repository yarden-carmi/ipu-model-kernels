{# gemm then add of a patches-view residual: the residual row is added to the tile's accumulator before the one store.
   Flat merge cursor (LR8, LR9) skips physical padding at each d3 boundary. Each output tile streams six weight
   digits for bias and each reduction lane. Residual row of output row (b, p) and tile t: (4 * p + b) * tiles + t
   (LR11 walks it; LR13 = its row base - 1, LR14 = b * tiles - 1, LR12 counts the p of one b down). #}
{% set tiles_n = (out0_d2 + 127) // 128 %}
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
    DEC LR9 1 ; SET LR12 CR0 ; SET LR13 CR0 ;;
    DEC LR13 1 ; INC LR12 {{ out0_d1 }} ; SET LR14 CR0 ;;
    DEC LR14 1 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ; SET LR11 LR13 ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR3 LR9 ; SET LR7 {{ cr.s0_k }} ;;
{% if s0_bias %}
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
    LD.MULT R1 LR11 {{ cr.in1 }} ; INC LR11 1 ; DEC LR6 1 ;;
    MULT.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    BEQ LR6 CR0 last_tile ;;
{{ store(cr.full) }}
    INC LR5 1 ; B tile ;;
last_tile:
{{ store(cr.tail) }}
    INC LR5 1 ; SET LR8 LR2 ; SET LR9 LR3 ;;
    INC LR13 {{ 4 * tiles_n }} ; DEC LR12 1 ; DEC LR10 1 ;;
    BNE LR12 CR0 same_b ;;
    INC LR14 {{ tiles_n }} ; SET LR12 CR0 ;;
    SET LR13 LR14 ; INC LR12 {{ out0_d1 }} ;;
same_b:
    BNE LR10 CR0 row ;;
    HALT ;;
