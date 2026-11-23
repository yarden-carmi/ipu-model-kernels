{# Replay the merged input cursor for each output tile. LR1 is its row,
   LR2 its lane, LR3 and LR4 count down d3 and d2 respectively. #}
{% macro load(slot) %}LD.MULT.CYCLIC LR6 {{ cr.w }} {{ slot }} ; INC LR6 1{% endmacro %}
{# Full d3 groups can prefetch the next activation on the final weight plane.
   Peel each group's last scalar so the prefetch never crosses a group. #}
{% set pipeline = in0_d3 > 1 and k % in0_d3 == 0 %}
{% macro dot(scalar, first=false, prefetch=false) %}
    {{ load('LR0') }}{% if not first %} ; DEC LR3 1 ; DEC LR8 1{% endif %} ;;
{% for p in range(3) %}
    MULT.RC.VE {{ 'LR15' if p % 2 else 'LR0' }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first and p == 0 %}.FIRST{% endif %}{% if p < 2 %} ; {{ load('LR0' if p % 2 else 'LR15') }}{% elif prefetch %} ; LD.MULT R0 LR1 {{ cr.in0 }} ; BNE LR3 CR0 prefetched{% elif not first and not pipeline %} ; BNE LR3 CR0 next_scalar{% endif %}{% if not first and p == 0 %} ; ADD LR1 LR1 {{ cr.chunks }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR15 CR0 ; SET LR7 CR0 ;;
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 {{ cr.in0_d3 }} ;;
    INC LR15 128 ; SET LR4 {{ cr.in0_d2 }} ; SET LR14 {{ cr.rows }} ;;
row:
    SET LR10 LR1 ; SET LR11 LR2 ; SET LR12 LR3 ;;
    SET LR6 CR0 ; SET LR9 {{ cr.tiles }} ; SET LR13 LR4 ;;
    DEC LR6 1 ;;
tile:
    SET LR1 LR10 ; SET LR2 LR11 ; SET LR3 LR12 ;;
    SET LR8 {{ cr.k }} ; SET LR4 LR13 ;;
{{ dot('CR1' if bias else 'CR0', true) }}
scalar:
    LD.MULT R0 LR1 {{ cr.in0 }}{% if pipeline %} ; DEC LR3 1{% endif %} ;;
{% if pipeline %}
prefetched:
{{ dot('LR2', prefetch=true) }}
{% endif %}
{{ dot('LR2') }}
    SET LR3 {{ cr.in0_d3 }} ; DEC LR4 1 ; INC LR2 1 ;;
    BEQ LR4 CR0 next_head ;;
    SUB LR1 LR1 {{ cr.head_stride }} ;;
    BNE LR2 LR15 next_scalar ;;
    INC LR1 1 ; SET LR2 CR0 ; B next_scalar ;;
next_head:
    SUB LR1 LR1 {{ cr.chunks }} ; SET LR4 {{ cr.in0_d2 }} ;;
    INC LR1 1 ; SET LR2 CR0 ;;
next_scalar:
    BNE LR8 CR0 scalar ;;
    DEC LR9 1 ;;
    BEQ LR9 CR0 last_tile ;;
{{ store(cr.full) }}
    B tile ;;
last_tile:
{{ store(cr.tail) }}
    DEC LR14 1 ;;
    BNE LR14 CR0 row ;;
    HALT ;;
