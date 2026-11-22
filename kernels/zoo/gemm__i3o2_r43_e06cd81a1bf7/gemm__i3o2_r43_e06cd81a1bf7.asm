{# Stream one vector per reduction element, prefetching the next weight
   in the same word. LR8/LR11 save the input row/lane across output tiles. #}
{% macro load_weight() %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    DEC LR5 1 ; SET LR10 {{ cr.rows }} ; SET LR11 CR0 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
    {{ load_weight() }} ;;
tile:
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ load_weight() }} ; SET LR2 LR8 ; SET LR3 LR11 ;;
    SET LR7 {{ cr.k }} ;;
chunk:
    {# MULT uses the incremented scalar index; COND compares the old index. #}
    LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR3 1 ;;
lane:
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ load_weight() }} ; INC LR3 1 {% if k % in0_d3 == 0 %}; BNE LR3 {{ cr.last_lane }} lane{% else %}; DEC LR7 1 ; BEQ LR3 {{ cr.last_lane }} advance{% endif %} ;;
{% if k % in0_d3 != 0 %}
    BNE LR7 CR0 lane ;;
    INC LR3 1 ; B finish ;;
advance:
{% endif %}
    INC LR2 1 ; SET LR3 CR0 {% if k % in0_d3 == 0 %}; SUB LR7 LR7 {{ cr.in0_d3 }}{% endif %} ;;
    BNE LR7 CR0 chunk ;;
finish:
    DEC LR6 1 ;;
    BEQ LR6 CR0 last_tile ;;
    {{ store(cr.full) }}
    B tile ;;
last_tile:
    {{ store(cr.tail) }}
    SET LR8 LR2 ; SET LR11 LR3 ; DEC LR10 1 ;;
    BNE LR10 CR0 row ;;
    HALT ;;
