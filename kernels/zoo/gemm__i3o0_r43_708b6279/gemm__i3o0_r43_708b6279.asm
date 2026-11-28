{% set p = 2 if in0_d3 <= 64 and k % (2 * in0_d3) == 0 else 1 %}
{% set positions = in0_d2 %}
{% set width = p * in0_d3 %}
{% set blocks = k // width %}
{% set short = positions == 16 %}
{% set tiles = 1 if short else positions // 32 %}
{% set quarters = positions // 4 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = qi %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% macro copy(q=qi) %}MULT.VE LR9 CR1 0 LR9 {{ ds }} {{ q }}{% endmacro %}
{% macro move() %}{{ copy() }} ; ACC.RESHAPE LRD0 LRD2 0{% endmacro %}
{# The merge view takes consecutive physical panels for each logical token.
   Gather eight K channels for four positions across the four heads. #}
    SET LR11 CR0 ; SET LR12 CR0 ;;
    DEC LR11 1 ;;
    SET LR14 CR0 ; SET LR9 CR0 ;;
split:
    SET LR0 LR13 ; SET LR1 LR7 ; SET LR15 CR0 ;;
chart:
    SET LR4 LR12 ; SET LR5 CR0 ;;
four:
    SET LR6 LR4 ; SET LR2 LR10 ; SET LR3 LR8 ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
{% for h in range(4) %}
{% for j in range(4) %}
    {{ move() }} ;
{% if j > 0 %} ADDBI LRD2 8 ;
{% elif h > 0 %} ADDBI LRD2 -22 ;{% endif %}
{% if not loop.last %} INC LR6 {{ blocks }} ; LD.MULT R0 LR6 {{ cr.in0 }} ; {% if h == 3 and j == 2 %} INC LR4 {{ 4*blocks }} ;{% endif %}
{% elif h < 3 %} ADD LR6 LR6 {{ cr.head_jump }} ; LD.MULT R0 LR6 {{ cr.in0 }} ;
{% else %} ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.mid }} LR11 ; INC LR11 1 ; INC LR5 1 ; BLT.S LR5 {{ cr.lastq_channel }}.L four ;
{% endif %} ;;
{% endfor %}
{% endfor %}
    ADDBI LRD0 8 ; INC LR15 1 ; BLT.S LR15 {{ cr.chart_split }}.L chart ;;
    INC LR12 1 ; INC LR14 1 ; BLT.S LR14 {{ cr.chart_split }}.H split ;;

{# First decimation selects a pair of channels for a half-tile of tokens. #}
{% macro stripe(h, v, offset, end) %}
    {{ copy() }} ; ACC.STRIDE 32 {{ h }} {{ v }} {{ offset }} ;
    {% if not end %}INC LR4 1 ; LD.MULT R0 LR4 {{ cr.mid }} ;
    {% else %}ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pairs }} LR11 ; INC LR11 1 ;{% endif %} ;;
{% endmacro %}
    SET LR1 CR1 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR2 2 ; INC LR3 3 ;;
    SET LR5 CR0 ;;
    SET LR11 CR0 ; SET LR6 CR0 ;;
    DEC LR11 1 ;;
    SET LR8 CR0 ;;
    INC LR8 {{ positions//16 - 1 }} ;;
pack_half:
    SET LR7 LR5 ; SET LR12 CR0 ;;
pack_group:
{% for ch in range(4) %}
    SET LR4 LR7 ; LD.MULT R0 LR4 {{ cr.mid }} ;;
{% for s in range(4) %}
    {{ stripe('on' if ch % 2 == 0 else 'on_inv', 'on' if ch < 2 else 'on_inv', 'LR9' if s == 0 else 'LR' ~ s, s == 3) }}
{% endfor %}
{% endfor %}
    INC LR7 {{ quarters }} ; INC LR12 1 ; BLT.S LR12 {{ cr.group_tile }}.L pack_group ;;
{% if not short %}
    INC LR5 4 ; INC LR6 1 ; BLT.S LR6 LR8 pack_half ;;
{% endif %}

{# Second decimation separates the pair and joins the two half-tiles. #}
    SET LR11 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR8 CR0 ;;
    INC LR8 {{ k//2 }} ;;
    DEC LR11 1 ;;
join_tile:
    SET LR7 LR5 ; SET LR12 CR0 ;;
join_group:
{% macro join(ch) %}
    SET LR4 LR7 ; LD.MULT R0 LR4 {{ cr.pairs }} ;;
    {{ copy() }} ; ACC.STRIDE 16 off {{ 'on' if ch < 4 else 'on_inv' }} LR9 ;
    {% if not short %} ADD LR4 LR4 LR8 ; LD.MULT R0 LR4 {{ cr.pairs }} ;;
    {{ copy() }} ; ACC.STRIDE 16 off {{ 'on' if ch < 4 else 'on_inv' }} LR2 ;{% endif %}
    ACTIVATE.QUANTIZE identity {{ 'CR7.H' if short else ds }} {{ qw }} {{ cr.panel }} LR11 ; INC LR11 1 ;
    {% if ch == 3 %} DEC LR7 3 ;{% elif ch < 7 %} INC LR7 1 ;{% else %} INC LR7 1 ; INC LR12 1 ; BLT.S LR12 {{ cr.group_tile }}.L join_group ;{% endif %} ;;
{% endmacro %}
{% for ch in range(8) %}{{ join(ch) }}{% endfor %}
{% if not short %}
    ADD LR5 LR5 LR8 ;;
    ADD LR5 LR5 LR8 ; INC LR6 1 ; BLT.S LR6 {{ cr.group_tile }}.H join_tile ;;
{% endif %}

{# Bias initializes R_ACC; the reduction streams one activation vector per cycle.
   For a 16-position plane, store only the first 64 lanes. #}
{% set wc = 128 %}
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
    SET LR10 CR0 ; SET LR14 CR0 ;;
    INC LR7 {{ k//wc - 1 if k >= wc else 0 }} ; INC LR14 {{ wc-3 }} ; DEC LR5 1 ;;
    SET LR11 LR5 ; SET LR12 CR0 ; ADD LR10 LR5 LR5 ;;
    INC LR10 {{ k % wc - 1 if k % wc >= 1 else 0 }} ;;
out_channel:
    SET LR13 CR0 ; SET LR4 CR0 ;;
out_tile:
    LD.MULT R0 LR6 {{ cr.w }} ; SET LR1 LR6 ; SET LR2 LR4 ; SET LR3 LR5 ;;
    {{ copy(qw) }} ; ACC.ADD.FIRST ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.w }} ; SET LR15 CR0 ;;
    LD.MULT.CYCLIC LR2 {{ cr.panel }} LR9 ; INC LR4 {{ k }} ;;
{% macro mac() %}MULT.RC.VE LR9 LR3 0 LR9 {{ ds }} {{ qw }} ; ACC.ADD{% endmacro %}
{% for blocklen in [wc, k % wc] %}
{% if (blocklen == wc and k >= wc) or (loop.last and blocklen > 0) %}
{% set label = 'chunk' if blocklen == wc else 'tail' %}
{% if blocklen > 1 %}
{{ label }}_mac:
    {{ mac() }} ; LD.MULT.CYCLIC LR2 {{ cr.panel }} LR9 ; INC LR2 1 ; INC LR3 1 ; BLT.S LR3 {{ 'LR14' if blocklen == wc else 'LR10' }} {{ label }}_mac ;;
{% endif %}
    {{ mac() }} ; INC LR3 1 ;
{% if blocklen == wc %}
{% if k > wc %}
    BEQ LR15 LR7 blocks_done ;;
    INC LR1 1 ; LD.MULT R0 LR1 {{ cr.w }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.panel }} LR9 ; INC LR2 1 ; SET LR3 LR5 ; INC LR15 1 ; B chunk_mac ;;
blocks_done:
{% if k % wc %}
    INC LR1 1 ; LD.MULT R0 LR1 {{ cr.w }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.panel }} LR9 ; INC LR2 1 ; SET LR3 LR5 ;;
{% endif %}
{% endif %}
{% endif %}
{% endif %}
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ 'CR7.H' if short else ds }} {{ qo }} {{ cr.out0 }} LR11 ; INC LR11 1 ; INC LR13 1 ; BLT.S LR13 {{ cr.group_tile }}.H out_tile ;;
    SET LR6 LR1 ;;
    INC LR6 1 ; INC LR12 1 ; BLT.S LR12 {{ cr.lastq_channel }}.H out_channel ;;
    HALT ;;
