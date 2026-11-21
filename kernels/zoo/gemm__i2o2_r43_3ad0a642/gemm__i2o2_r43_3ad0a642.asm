{# The merge reads the original storage linearly. For each group of d3
   scalars, walk the physical rows at the lane-chunk stride. LR10 tracks
   the logical sequence position and LR3 the lane within its chunk. #}
{% macro dot(s, first=false) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 {% if not first %}; DEC LR7 1{% endif %} ;;
{% for p in range(4) %}
    MULT.RC.VE {{ 'LR1' if p % 2 else 'LR0' }} {{ s }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first and p == 0 %}.FIRST{% endif %}{% if p < 3 %} ; LD.MULT.CYCLIC LR4 {{ cr.w }} {{ 'LR0' if p % 2 else 'LR1' }} ; INC LR4 1{% elif not first %} ; ADD LR2 LR2 {{ cr.chunks }} ; BNE LR7 CR0 input{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR11 CR0 ;;
    SET LR12 {{ cr.rows }} ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR3 LR9 ; SET LR10 LR11 ;;
    SET LR13 {{ cr.in0_d1 }} ;;
{% if bias %}
{{ dot('CR1', true) }}
{% else %}
{{ dot('CR0', true) }}
{% endif %}
group:
    SET LR7 {{ cr.in0_d3 }} ; SET LR15 LR2 ;;
input:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{{ dot('LR3') }}
    INC LR10 1 ; INC LR3 1 ; DEC LR13 1 ;;
    BEQ LR10 {{ cr.in0_d2 }} sequence_end ;;
    BEQ LR3 LR1 chunk_end ;;
    B group_done ;;
chunk_end:
    SET LR3 CR0 ; INC LR15 1 ;;
    B group_done ;;
sequence_end:
    SET LR10 CR0 ; SET LR3 CR0 ; ADD LR15 LR15 {{ cr.wrap }} ;;
group_done:
    SET LR2 LR15 ;;
    BNE LR13 CR0 group ;;
    DEC LR6 1 ;;
    BEQ LR6 CR0 last_tile ;;
{{ store(cr.full) }}
    INC LR5 1 ; B tile ;;
last_tile:
{{ store(cr.tail) }}
    SET LR8 LR2 ; SET LR9 LR3 ; SET LR11 LR10 ;;
    INC LR5 1 ; DEC LR12 1 ;;
    BNE LR12 CR0 row ;;
    HALT ;;
