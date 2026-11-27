{% if true %}
{# LR8:LR9 is the merge cursor (physical row, logical lane minus one).
   Restart each output tile from that cursor and skip physical padding. #}
{% macro load_weight(slot) -%}
LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1
{%- endmacro %}
{% macro mac(slot, scalar, first=false) -%}
MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro dot(scalar, first=false) %}
{% if not first %}    INC LR3 1 ; DEC LR7 1 ;; {% endif %}
{# The first plane is already loaded. Each MAC loads the following plane;
   the last MAC may overwrite its own slot because MULT reads before LOAD. #}
{% for p in range(2) %}
    {{ mac('LR1' if p % 2 else 'LR0', scalar, first and p == 0) }} ; {{ load_weight('LR0' if p % 2 else 'LR1') }} ;;
{% endfor %}
{% if not first %}    BNE LR3 LR11 lane ;; {% endif %}
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
    {{ load_weight('LR0') }} ;;
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
{% else %}
{% macro load_weight() %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    DEC LR5 1 ; SET LR10 {{ cr.rows }} ; SET LR11 CR0 ;;
row:
    SET LR4 {{ cr.minusone }} ; SET LR6 {{ cr.tiles }} ;;
    {{ load_weight() }} ;;
tile:
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ load_weight() }} ; SET LR2 LR8 ; {% if k % in0_d3 == 0 and in0_d3 == 64 %}SET LR7 {{ cr.k }}{% else %}SET LR3 LR11{% endif %} ;;
{% if not (k % 128 == 0 and 128 == 64) %}
    SET LR7 {{ cr.k }} ;;
{% endif %}
chunk:
{% if k % 128 == 0 and 128 == 64 %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR3 {{ cr.minusone }} ;;
{% else %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR3 1 ;;
{% endif %}
{% if k % 128 == 0 and 128 == 64 %}
{% macro fastmac(i) %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ load_weight() }} ; INC LR3 1 {% if i == 61 %}; SUB LR7 LR7 {{ cr.in0_d3 }}{% elif i == 62 %}; INC LR2 1{% elif i == 63 %}; BNE LR7 CR0 chunk{% endif %} ;;
{% endmacro %}
{% for i in range(32) %}{{ fastmac(i * 2) }}{{ fastmac(i * 2 + 1) }}{% endfor %}
{% else %}
lane:
{% if k % 128 == 0 %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ load_weight() }} ; INC LR3 1 ;;
{% endif %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ load_weight() }} ; INC LR3 1 {% if k % 128 == 0 %}; BNE LR3 {{ cr.last_lane }} lane{% else %}; DEC LR7 1 ; BEQ LR3 {{ cr.last_lane }} advance{% endif %} ;;
{% if k % 128 != 0 %}
    BNE LR7 CR0 lane ;;
    INC LR3 1 ; B finish ;;
advance:
{% endif %}
    INC LR2 1 ; SET LR3 CR0 {% if k % 128 == 0 %}; SUB LR7 LR7 {{ cr.in0_d3 }}{% endif %} ;;
    BNE LR7 CR0 chunk ;;
{% endif %}
finish:
    DEC LR6 1 ; BEQ LR6 CR1 last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; B tile ;;
last_tile:
    {{ store(cr.tail) }}
    SET LR8 LR2 ; SET LR11 {% if k % in0_d3 == 0 and in0_d3 == 64 %}CR0{% else %}LR3{% endif %} ; DEC LR10 1 ;;
    BNE LR10 CR0 row ;;
    HALT ;;
{% endif %}
