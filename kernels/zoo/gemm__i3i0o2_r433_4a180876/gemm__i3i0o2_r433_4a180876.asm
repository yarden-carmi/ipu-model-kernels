    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    DEC LR2 1 ;;
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR11 LR15 ;;
    SET LR12 CR0 ;;
copy_batch:
    SET LR0 LR12 ; SET LR3 CR0 ; SET LR10 LR14 ;;
copy_row:
    SET LR1 LR3 ; SET LR9 {{ cr.tiles }} ;;
copy_tile:
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
copy_column:
    LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.EE LR0 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD4 LRD6 7 ; ADD LR1 LR1 LR13 ; INC LR8 1 ;;
    ADDBI LRD6 1 ; BLT.S LR8 {{ cr.slot }} copy_column ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ; DEC LR9 1 ; BNE LR9 CR1 copy_tile ;;
    ADD LR2 LR2 {{ cr.tiles }} ; ADD LR0 LR0 LR15 ; DEC LR10 1 ;;
    BEQ LR10 CR0 copy_batch_end ;;
    BLT.S LR0 {{ cr.slot }} copy_row ;;
    SET LR0 LR12 ; INC LR3 1 ; B copy_row ;;
copy_batch_end:
    INC LR12 1 ; DEC LR11 1 ; BNE LR11 CR1 copy_batch ;;
{% macro load_weight() %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 {{ cr.tiles }} ; SET LR8 CR0 ;;
    DEC LR5 1 ; SET LR10 {{ cr.rows }} ; SET LR11 CR0 ;;
    SET LR12 {{ cr.in0_d3 }} ;;
    DEC LR12 2 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
    {{ load_weight() }} ;;
tile:
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ load_weight() }} ; SET LR2 LR8 ; {% if k % in0_d3 == 0 and in0_d3 == 64 %}SET LR7 {{ cr.k }}{% else %}SET LR3 LR11{% endif %} ;;
{% if not (k % in0_d3 == 0 and in0_d3 == 64) %}
    SET LR7 {{ cr.k }} ;;
{% endif %}
chunk:
{% if k % in0_d3 == 0 and in0_d3 == 64 %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR3 CR0 ;;
    DEC LR3 1 ;;
{% else %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR3 1 ;;
{% endif %}
{% if k % in0_d3 == 0 and in0_d3 == 64 %}
{% macro fastmac(i) %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ load_weight() }} ; INC LR3 1 {% if i == 61 %}; SUB LR7 LR7 {{ cr.in0_d3 }}{% elif i == 62 %}; INC LR2 1{% elif i == 63 %}; BNE LR7 CR0 chunk{% endif %} ;;
{% endmacro %}
{% for i in range(32) %}{{ fastmac(i * 2) }}{{ fastmac(i * 2 + 1) }}{% endfor %}
{% else %}
lane:
{% if k % in0_d3 == 0 and in0_d3 % 2 == 0 %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ load_weight() }} ; INC LR3 1 ;;
{% endif %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ load_weight() }} ; INC LR3 1 {% if k % in0_d3 == 0 %}; BNE LR3 LR12 lane{% else %}; DEC LR7 1 ; BEQ LR3 LR12 advance{% endif %} ;;
{% if k % in0_d3 != 0 %}
    BNE LR7 CR0 lane ;;
    INC LR3 1 ; B finish ;;
advance:
{% endif %}
    INC LR2 1 ; SET LR3 CR0 {% if k % in0_d3 == 0 %}; SUB LR7 LR7 {{ cr.in0_d3 }}{% endif %} ;;
    BNE LR7 CR0 chunk ;;
{% endif %}
finish:
    DEC LR6 1 ; BEQ LR6 CR1 last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; B tile ;;
last_tile:
    {{ store(cr.tail) }}
    SET LR8 LR2 ; SET LR11 {% if k % in0_d3 == 0 and in0_d3 == 64 %}CR0{% else %}LR3{% endif %} ; DEC LR10 1 ;;
    ADD LR5 LR5 {{ cr.tiles }} ;;
    BNE LR10 CR0 row ;;
    HALT ;;
