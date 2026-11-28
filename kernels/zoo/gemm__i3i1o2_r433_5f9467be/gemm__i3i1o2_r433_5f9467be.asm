{% if false %}
{# LR8:LR9 is the merge cursor (physical row, logical lane minus one).
   Restart each output tile from that cursor and skip physical padding. #}
{% macro load_weight(slot) -%}
LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1
{%- endmacro %}
{% macro mac(slot, scalar, first=false) -%}
MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro dot(scalar, first=false) %}
{# The first plane is already loaded. Each MAC loads the following plane;
   the last MAC may overwrite its own slot because MULT reads before LOAD. #}
{% for p in range(3) %}
    {{ mac('LR1' if p % 2 else 'LR0', scalar, first and p == 0) }} ; {{ load_weight('LR1' if p == 0 else 'LR0') }}{% if not first and p == 0 %} ; INC LR3 1 ; DEC LR7 1{% elif not first and p == 2 %} ; BNE LR3 LR11 lane{% endif %} ;;
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
    {{ load_weight('LR0') }} ;;
tile:
    SET LR2 LR8 ; SET LR3 LR9 ; SET LR7 {{ cr.k }} ;;
    {{ dot('CR1', true) }}
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
    SET LR9 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
    SET LR13 CR0 ; DEC LR5 1 ;;
    INC LR13 {{ in1_d0 }} ;;
copy_batch:
    SET LR12 CR0 ;;
{% for i in range((in1_d1 + 126) // 127) %}
    INC LR12 {{ [127, in1_d1 - i * 127] | min }} ;;
{% endfor %}
copy_row:
    SET LR14 LR10 ; SET LR6 CR0 ;;
    DEC LR14 {{ (in1_d1 + 127) // 128 }} ;;
    INC LR6 {{ (in1_d2 + 127) // 128 }} ;;
copy_tile:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR7 CR0 ;;
    INC LR7 128 ;;
{% if in1_d2 % 128 %}
    BNE LR6 CR1 copy_gather ;;
    SET LR7 CR0 ; INC LR7 {{ in1_d2 % 128 }} ;;
{% endif %}
copy_gather:
    LD.MULT R0 LR14 {{ cr.in1 }} ; INC LR14 {{ (in1_d1 + 127) // 128 }} ;;
copy_gather_loop:
    MULT.EE LR11 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD8 LRD2 7 ; DEC LR7 1 ; BEQ LR7 CR1 copy_gather_done ;;
    LD.MULT R0 LR14 {{ cr.in1 }} ; INC LR14 {{ (in1_d1 + 127) // 128 }} ; ADDBI LRD2 1 ; B copy_gather_loop ;;
copy_gather_done:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; DEC LR6 1 ; BNE LR6 CR1 copy_tile ;;
    INC LR5 {{ (n + 127) // 128 }} ; DEC LR12 1 ; BEQ LR12 CR1 copy_next_batch ;;
    INC.MODP2 LR11 CR1 7 ;;
    BNE LR11 CR0 copy_row ;;
    INC LR10 1 ; B copy_row ;;
copy_next_batch:
    DEC LR13 1 ; BEQ LR13 CR1 copy_done ;;
    SET LR10 LR14 ; SET LR11 CR0 ;;
    INC LR10 1 ;;
    B copy_batch ;;
copy_done:
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    INC LR5 {{ (in1_d2 + 127) // 128 - 1 }} ; SET LR10 {{ cr.rows }} ;;
    SET LR11 CR0 ;;
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
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ load_weight() }} ; INC LR3 1 {% if k % in0_d3 == 0 %}; BNE LR3 {{ cr.last_lane }} lane{% else %}; DEC LR7 1 ; BEQ LR3 {{ cr.last_lane }} advance{% endif %} ;;
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
    INC LR5 {{ (in1_d2 + 127) // 128 }} ;;
    BNE LR10 CR0 row ;;
    HALT ;;
{% endif %}
