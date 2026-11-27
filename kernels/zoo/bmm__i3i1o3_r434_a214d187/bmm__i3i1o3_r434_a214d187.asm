{# Reuse one A chunk across the columns of an output tile. The final
   K chunk uses its actual width; each column accumulates in its own slot. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR14 CR0 ; SET LR15 CR0 ;;
    INC LR14 128 ;;
group:
    SET LR4 {{ cr.rows_heads }}.H ;;
head:
    SET LR5 {{ cr.rows_heads }}.L ;;
    SET LR6 CR0 ;;
    INC LR6 62 ;;
    BNE LR6 {{ cr.n_limits }}.L row ;;
    ADD LR6 LR14 LR14 ;;
    ADD LR7 LR6 LR6 ;;
    ADD LR8 LR7 LR7 ;;
    ADD LR6 LR6 LR7 ;;
    ADD LR6 LR6 LR8 ;;
    BLE.S {{ cr.widths }}.L LR6 row ;;
    ADD LR6 LR6 LR14 ;;
    BLT.S {{ cr.widths }}.L LR6 pair_head ;;
row:
    SET LR6 LR1 ; SET LR7 {{ cr.n_limits }}.L ;;
    INC LR7 2 ;;
tile:
    SET LR8 LR0 ; SET LR9 LR6 ; SET LR10 {{ cr.widths }}.L ;;
    SET LR11 LR7 ; BLE.S LR7 LR14 first ;;
    SET LR11 LR14 ;;
first:
    DEC LR11 3 ; BGT.S LR10 LR14 first_full ;;
    B first_tail ;;

{% macro dot(half, first) %}
    MULT.RC.VV LR15 R0 0 LR15 {{ cr.k_widths }}.{{ half }} {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR12 {{ cr.k_widths }}.{{ half }} ; INC LR12 1 ; ADD LR13 LR13 {{ cr.strides }}.H
{%- endmacro %}

{% macro columns(tag, half, first) %}
{{ tag }}:
    SET LR12 CR0 ; SET LR13 LR9 ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
    DEC LR12 1 ; LD.MULT.CYCLIC LR13 {{ cr.in1 }} LR15 ;;
    BLT.S LR11 LR12 {{ tag }}_last ;;
{{ tag }}_col:
    {{ dot(half, first) }} ; LD.MULT.CYCLIC LR13 {{ cr.in1 }} LR15 ; BLT.S LR12 LR11 {{ tag }}_col ;;
{{ tag }}_last:
    {{ dot(half, first) }} ;;
{% if half == 'L' %}
    INC LR8 1 ; INC LR9 1 ; SUB LR10 LR10 LR14 ;;
    BGT.S LR10 LR14 more_full ;;
    B more_tail ;;
{% else %}
    B store ;;
{% endif %}
{% endmacro %}
    {{ columns('first_full', 'L', true) }}
    {{ columns('first_tail', 'H', true) }}
    {{ columns('more_full', 'L', false) }}
    {{ columns('more_tail', 'H', false) }}

{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {% if half == 'H' %}{{ cr.widths }}.H{% else %}{{ cr.k_widths }}.L{% endif %} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
{% endmacro %}
store:
    BGT.S LR7 LR14 full ;;
    {{ output('H') }}
    SUB LR8 LR8 LR0 ;;
    ADD LR0 LR0 {{ cr.strides }}.L ; DEC LR5 1 ; BGT.S LR5 CR1 row ;;
    SUB LR1 LR13 LR8 ; DEC LR4 1 ; BGT.S LR4 CR1 head ;;
    ADD LR0 LR0 {{ cr.a_gap }} ; ADD LR1 LR1 {{ cr.b_gap }} ; DEC LR3 1 ; BGT.S LR3 CR1 group ;;
    HALT ;;
full:
    {{ output('L') }}
    SUB LR8 LR8 LR0 ; SUB LR7 LR7 LR14 ;;
    SUB LR6 LR13 LR8 ; B tile ;;

{# A transposed RHS fringe lets each remaining key contribute to all 64
   columns in one word. The full K rows use two interleaved queries so
   the unused load slots can prefetch both queries' next K row. #}
pair_head:
    SET LR8 LR1 ; SET LR6 {{ cr.widths }}.L ; SET LR7 CR0 ;;
    INC LR8 14 ; INC.MODP2 LR6 CR0 7 ; SET LR11 {{ cr.n_limits }}.L ;;
    DEC LR11 1 ; SET LR12 LR14 ; SET LR13 LR14 ;;
    ADD LR13 LR14 LR14 ; DEC LR6 1 ;;
    ADD LR12 LR13 LR14 ;
    MULT.VE LR15 CR0 0 LR15 {{ cr.k_widths }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.k_widths }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR14 ;;
{% macro gather() %}
    MULT.EE LR7 CR1 0 LR15 {{ cr.k_widths }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR10 {{ cr.n_limits }}.H
{%- endmacro %}
panel_key:
    SET LR9 LR8 ; SUB LR10 LR15 CR1 ; LD.MULT R0 LR8 {{ cr.in1 }} ;;
panel_col:
    INC LR10 1 ; ADD LR9 LR9 {{ cr.strides }}.H ; LD.MULT R0 LR9 {{ cr.in1 }} ;
    {{ gather() }} ; BLT.S LR10 LR11 panel_col ;;
    INC LR10 1 ; {{ gather() }} ;
    ACTIVATE.QUANTIZE identity {{ cr.widths }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR7 ;;
    INC LR7 1 ; BLT.S LR7 LR6 panel_key ;;

pair_row:
    SET LR6 LR0 ; ADD LR7 LR0 {{ cr.strides }}.L ; BLE.S LR5 CR1 pair_odd ;;
pair_ready:
    INC LR6 14 ; INC LR7 14 ; SET LR8 {{ cr.widths }}.L ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
    INC.MODP2 LR8 CR0 7 ; SET LR11 {{ cr.n_limits }}.L ; LD.MULT R1 LR7 {{ cr.in0 }} ;;
    INC LR11 2 ; DEC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.panel }} LR14 ;;
    ADD LR9 LR8 LR14 ; LD.MULT.CYCLIC LR14 {{ cr.panel }} LR15 ; BEQ LR8 CR0 tail_only ;;

{% macro tail_mac(slot, scalar, first=false) %}
    MULT.RC.VE {{ slot }} {{ scalar }} 0 LR15 {{ cr.k_widths }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }}
{%- endmacro %}
    {{ tail_mac('LR14', 'LR8', true) }} ;;
    {{ tail_mac('LR11', 'LR9') }} ; DEC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.panel }} LR14 ; BLE.S LR8 CR1 tail_last ;;
tail_loop:
    {{ tail_mac('LR14', 'LR8') }} ; ADD LR9 LR8 LR14 ;;
    {{ tail_mac('LR11', 'LR9') }} ; DEC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.panel }} LR14 ; BGT.S LR8 CR1 tail_loop ;;
tail_last:
    {{ tail_mac('LR14', 'LR15') }} ; DEC LR6 14 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR13 ; B tail_drain ;;
tail_only:
    {{ tail_mac('LR14', 'LR15', true) }} ; DEC LR6 14 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR13 ;;
tail_drain:
    {{ tail_mac('LR11', 'LR14') }} ; DEC LR7 14 ; LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR12 ; SET LR8 LR1 ; SET LR10 CR0 ;;
    SET LR9 LR8 ; LD.MULT R0 LR8 {{ cr.in1 }} ;;

{% macro pair_dot(idx, col) %}
    MULT.RC.VV {{ idx }} R0 0 LR15 {{ cr.k_widths }}.L {{ cr.qf_in0 }}.L ; AGG.SUM {{ col }} {{ cr.k_widths }}.L
{%- endmacro %}
{% macro next_column() %}
    ADD LR9 LR9 {{ cr.strides }}.H ; LD.MULT R0 LR9 {{ cr.in1 }}
{%- endmacro %}
{% macro chunk(i, a, b, next_a, next_b, last) %}
    {{ pair_dot(a, 'LR10') }} ; SET LR11 {{ cr.n_limits }}.L ;
    {% if not last %}INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} {{ next_a }} ;{% endif %} ;;
    {{ pair_dot(b, 'LR11') }} ; INC LR11 2 ; {{ next_column() }} ;;
    {{ pair_dot(a, 'LR10') }} ; INC LR10 1 ;
    {% if not last %}INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.in0 }} {{ next_b }} ;{% endif %} ;;
    {{ pair_dot(b, 'LR11') }} ; INC LR11 1 ; {{ next_column() }} ;;
pair_col_{{ i }}:
    {{ pair_dot(a, 'LR10') }} ; INC LR10 1 ;;
    {{ pair_dot(b, 'LR11') }} ; INC LR11 1 ; {{ next_column() }} ; BLT.S LR10 {{ cr.n_limits }}.L pair_col_{{ i }} ;;
    {{ pair_dot(a, 'LR10') }} ; INC LR10 1 ;
    {% if last %}
    {{ output_pair('LR2', false) }} ;;
    {{ pair_dot(b, 'LR11') }} ; INC LR11 1 ; INC LR2 1 ; BLE.S LR5 CR1 pair_head_end ;
    {{ output_pair('LR13', true) }} ;;
    {% else %}
    ADD LR9 LR8 CR1 ; INC LR8 1 ;;
    {{ pair_dot(b, 'LR11') }} ; INC LR11 1 ; SET LR10 CR0 ; LD.MULT R0 LR9 {{ cr.in1 }} ;;
    {% endif %}
{% endmacro %}
{% macro output_pair(ptr, packed) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {% if packed %}{{ cr.k_widths }}.L{% else %}{{ cr.widths }}.H{% endif %} {{ cr.qf_out0 }}.L {% if packed %}{{ cr.panel }}{% else %}{{ cr.out0 }}{% endif %} {{ ptr }}
{%- endmacro %}
{% for i in range(14) %}
    {% if i % 2 == 0 %}{{ chunk(i, 'LR13', 'LR12', 'LR15', 'LR14', i == 13) }}
    {% else %}{{ chunk(i, 'LR15', 'LR14', 'LR13', 'LR12', i == 13) }}{% endif %}
{% endfor %}
    SET LR11 {{ cr.n_limits }}.L ; LD.MULT.CYCLIC LR13 {{ cr.panel }} LR15 ;;
    INC LR11 2 ; DEC LR5 2 ; ADD LR0 LR0 {{ cr.strides }}.L ;
    MULT.RC.VE LR11 CR1 0 LR15 {{ cr.k_widths }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.widths }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; ADD LR0 LR0 {{ cr.strides }}.L ; BGT.S LR5 CR0 pair_row ;;
    B pair_advance_head ;;
pair_odd:
    SET LR7 LR0 ; B pair_ready ;;
pair_head_end:
    ADD LR0 LR0 {{ cr.strides }}.L ;;
pair_advance_head:
    ADD LR1 LR9 {{ cr.strides }}.H ;;
    DEC LR1 13 ; DEC LR4 1 ; BGT.S LR4 CR1 head ;;
    ADD LR0 LR0 {{ cr.a_gap }} ; ADD LR1 LR1 {{ cr.b_gap }} ; DEC LR3 1 ; BGT.S LR3 CR1 group ;;
    HALT ;;
