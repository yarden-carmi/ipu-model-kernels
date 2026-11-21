{% set tiles = (out0_d2 + 127) // 128 %}
{% set tail = (out0_d2 - 1) % 128 + 1 %}
{% set rtiles = (in1_d2 + 127) // 128 %}
{% set rem = s0_m % in1_d2 %}
{% macro inc(r, n) %}
{% for i in range(0, n, 255) %}
    INC {{r}} {{ [255, n-i]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro dot(s, stream=false) %}
{% for i in range(6) %}
    MULT.RC.VE {{ 'LR1' if i % 2 else 'LR0' }} {{s}} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR14 {{ cr.w }} {{ 'LR0' if i % 2 else 'LR1' }} ; INC LR14 1 {% if stream and i == 0 %}; INC LR3 1{% endif %}{% if stream and i == 5 %}; BNE LR3 {{ cr.last_lane }} lane{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ds}}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}

{# LR7=b, LR13=positions remaining. LR9:LR10 track the physical row
   base and logical channel of b+B*p. LR11:LR12 walk that same
   decomposition with stride B*P across channels, including tile boundaries. #}
    SET LR0 CR0 ; SET LR1 {{ cr.slot }} ; SET LR5 CR0 ;;
    SET LR7 CR0 ; SET LR8 CR0 ; SET LR3 CR0 ;;
    SET LR9 CR0 ; SET LR10 CR0 ; SET LR13 CR0 ;;
    DEC LR5 1 ; DEC LR8 1 ;;
{{ inc('LR13', out0_d1) }}
row:
    SET LR11 LR9 ; SET LR12 LR10 ; SET LR6 CR0 ;;
    INC LR6 {{tiles}} ;;
tile:
    SET LR15 CR0 ; SET LR2 {{ cr.slot }} ; DEC LR6 1 ;;
    BNE LR6 CR0 gather ;;
    SET LR2 CR0 ;;
    INC LR2 {{tail}} ;;
gather:
    SET LR3 LR11 ; SET LR4 LR12 ; BLT.S LR12 {{ cr.slot }} load_residual ;;
{% for i in range(1, rtiles) %}
    INC LR3 1 ; SUB LR4 LR4 {{ cr.slot }} {% if i < rtiles - 1 %}; BLT.S LR4 {{ cr.slot }} load_residual{% endif %} ;;
{% endfor %}
load_residual:
    LD.MULT R0 LR3 {{ cr.in1 }} ; ADD LR11 LR11 {{ cr.stepq }} ; INC LR12 {{ [255,rem]|min }} ; DEC LR2 1 ;;
{{ inc('LR12', [0,rem-255]|max) }}
    MULT.EE LR4 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD14 7 ; BLT.S LR12 {{ cr.in1_d2 }} gathered ;;
    SUB LR12 LR12 {{ cr.in1_d2 }} ; INC LR11 {{rtiles}} ;;
gathered:
    ADDBI LRD14 1 ; BNE LR2 CR0 gather ;;

{# Recreate the tile's weight cursor from the number of remaining tiles.
   LR14 is free after the gather (it is the unused low half of LRD14). #}
    SET LR14 CR0 ; SET LR4 CR0 ;;
    DEC LR14 1 ; INC LR4 {{tiles - 1}} ;;
{% if tiles > 1 %}
weight_tile:
    BEQ LR4 LR6 weight_ready ;;
    ADD LR14 LR14 {{ cr.weight_stride }} ; DEC LR4 1 ; B weight_tile ;;
weight_ready:
{% endif %}
    LD.MULT.CYCLIC LR14 {{ cr.w }} LR0 ; INC LR14 1 ; SET LR2 LR8 ; SET LR4 LR8 ;;
    INC LR4 {{in0_d1}} ;;
{{ dot('CR1') }}
group:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; SET LR3 CR0 ;;
    DEC LR3 1 ;;
lane:
{{ dot('LR3', true) }}
    BNE LR2 LR4 group ;;
    BEQ LR6 CR0 last_tile ;;
{{ store(cr.full) }}
    B tile ;;
last_tile:
{{ store(cr.tail) }}
    SET LR8 LR2 ; DEC LR13 1 ; INC LR10 {{out0_d0}} ;;
    BNE LR13 CR0 next_position ;;
    INC LR7 1 ; SET LR3 CR0 ;;
    INC LR3 {{out0_d0}} ;;
    BEQ LR7 LR3 done ;;
    SET LR9 CR0 ; SET LR10 LR7 ; SET LR13 CR0 ;;
{{ inc('LR13', out0_d1) }}
    B row ;;
next_position:
    BLT.S LR10 {{ cr.in1_d2 }} row ;;
    SUB LR10 LR10 {{ cr.in1_d2 }} ; INC LR9 {{rtiles}} ; B row ;;
done:
    HALT ;;
