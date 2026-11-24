{% macro store(kind, ds, qf, base, cursor) %}
    ACTIVATE.QUANTIZE {{ kind }} {{ ds }}.L {{ qf }}.L {{ base }} {{ cursor }} ;;
    INC {{ cursor }} 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
    INC LR2 1 ;;
{% endfor %}
    SET LR4 CR0 ; SET LR13 CR0 ; SET LR14 {{ cr.in0_d0 }} ;;
    SET LR12 CR0 ;;
    INC LR12 128 ;;
batch:
    SET LR5 LR4 ; SET LR6 CR0 ; SET LR7 CR0 ;;
feature:
    SET LR8 LR7 ; SET LR9 LR5 ; SET LR10 {{ cr.in0_d1 }} ;;
panel_tile:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR15 LR10 ;;
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    MULT.EE LR6 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    BLT.S LR10 LR12 gather ;;
    SET LR15 LR12 ;;
gather:
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    MULT.EE LR6 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR9 LR9 {{ cr.ik }} ; DEC LR15 1 ;;
    ADDBI LRD2 1 ; BNE LR15 CR0 gather ;;
    BLT.S LR12 LR10 panel_full ;;
    {{ store('identity', cr.tail, cr.qf_in0, cr.panel, 'LR8') }}
    INC LR7 1 ; INC LR6 1 ;;
    BGE.S LR7 {{ cr.k }} multiply ;;
    BLT.S LR6 LR12 feature ;;
    SET LR6 CR0 ; INC LR5 1 ; B feature ;;
panel_full:
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR8 ; DEC LR10 128 ;;
    ADD LR8 LR8 {{ cr.k }} ; B panel_tile ;;

{# Multiply one panel tile by one column of packed scalar weights. #}
{% macro mac(next_label='') %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 ; INC LR8 1 {% if next_label %}; LD.MULT.CYCLIC LR8 {{ cr.panel }} LR0 ; BLT.S LR3 LR2 {{ next_label }} {% endif %} ;;
{% endmacro %}
{% macro chunk(count, label) %}
    LD.MULT R0 LR11 {{ cr.w }} ; SET LR3 CR0 ; SET LR2 CR0 ;;
    LD.MULT.CYCLIC LR8 {{ cr.panel }} LR0 ; INC LR11 1 ; DEC LR3 1 {% if count > 3 %}; INC LR2 {{ count - 3 }} {% elif count == 2 %}; DEC LR2 1 {% endif %} ;;
{# LR3 is -1 before the first MAC; MULT sees the increment, BLT sees the old index. #}
{% if count > 1 %}
{{ label }}:
    {{ mac(label) }}
{% endif %}
    {{ mac() }}
{% endmacro %}
multiply:
    SET LR4 LR9 ; SET LR5 CR0 ; SET LR6 CR0 ;;
column:
    SET LR8 CR0 ; SET LR10 {{ cr.in0_d1 }} ;;
tile:
    SET LR11 LR5 ;;
    LD.MULT R0 LR11 {{ cr.w }} ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% if k > 128 %}
    SET LR7 CR0 ;;
    INC LR7 {{ (k - 1) // 128 }} ;;
reduce_chunk:
    {{ chunk(128, 'reduce_group') }}
    DEC LR7 1 ;;
    BNE LR7 CR0 reduce_chunk ;;
{% endif %}
    {{ chunk((k - 1) % 128 + 1, 'reduce_tail') }}
{% if k % 128 == 0 %}
    LD.MULT R0 LR11 {{ cr.w }} ; SET LR3 CR0 ;;
{% else %}
    INC LR3 1 ;;
{% endif %}
    MULT.EE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    BLT.S LR12 LR10 output_full ;;
    {{ store('generic', cr.tail, cr.qf_out0, cr.out0, 'LR13') }}
    SET LR5 LR11 ; INC LR6 1 ;;
{% if k % 128 == 0 %}
    INC LR5 1 ;;
{% endif %}
    BLT.S LR6 {{ cr.n }} column ;;
    DEC LR14 1 ;;
    BNE LR14 CR0 batch ;;
    HALT ;;
output_full:
    {{ store('generic', cr.full, cr.qf_out0, cr.out0, 'LR13') }}
    DEC LR10 128 ; B tile ;;
