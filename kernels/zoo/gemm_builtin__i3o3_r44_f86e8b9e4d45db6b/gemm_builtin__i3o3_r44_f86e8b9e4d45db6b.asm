{% macro coeff(reg) %}
    LD.MULT {{ reg }} LR11 {{ cr.w }} ; INC LR11 1
{%- endmacro %}
{% macro mac(src, mode) %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.tail_ds if tiles == 1 else cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro bias_row(mode) %}
    LD.MULT.CYCLIC LR11 {{ cr.w }} LR0 ; INC LR11 1 ;;
    {{ mac('CR1', mode) }} ;;
{%- endmacro %}
{% macro load_input() %}
{% if tiles == 1 %}
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; INC LR4 1
{%- else %}
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; ADD LR4 LR4 {{ cr.tile_or_pair_span }}
{%- endif %}
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR12 1
{%- endmacro %}
{% if in0_d3 <= 64 and in0_d2 <= 510 and in0_d2 % 8 == 0 and k <= 16 %}
{# Pair rows from the two halves of each plane in 64-lane slots. #}
{# Packed inputs start at scratch row 1; row 0 is used to unpack the second result. #}
{% macro pair_mac(src, mode) %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR8 CR0 ;;
    INC LR1 128 ; SET LR15 {{ cr.out0_d0 }} ; SET LR7 CR0 ;;
    INC LR7 64 ; SET LR5 CR0 ; SET LR10 CR0 ;;
    DEC LR5 1 ;;
pair_batch:
    SET LR4 LR8 ; SET LR12 LR8 ; SET LR13 CR0 ;;
    ADD LR12 LR12 {{ cr.tile_or_pair_span }} ; INC LR13 {{ pair_rows }} ;;
    SET LR14 LR13 ; SET LR10 CR0 ;;
    SET LR6 {{ cr.tile_or_pair_span }} ;;
    SET LR11 LR4 ; DEC LR4 1 ; DEC LR12 2 ;;
    INC LR10 2 ; DEC LR6 1 ;;
pack_input:
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ;;
    LD.MULT R0 LR12 {{ cr.in0 }} ; INC LR12 1 ; MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.STRIDE 64 off on LR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.STRIDE 64 off on LR10 ; ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.packed }} LR11 ; INC LR11 1 ; DEC LR6 1 ; BNE LR6 CR1 pack_input ;;
    SET LR9 CR0 ; SET LR6 {{ cr.n }} ;;
pair_channel:
    SET LR12 LR8 ; SET LR13 LR14 ; ADD LR3 LR5 LR14 ;;
pair_row:
    SET LR11 LR9 ; SET LR4 LR12 ;;
    LD.MULT.CYCLIC LR11 {{ cr.w }} LR0 ;;
    {{ pair_mac('CR1', 'ADD.FIRST') }} ; LD.MULT.CYCLIC LR11 {{ cr.w }} LR0 ; INC LR11 1 ;;
    {{ pair_mac('CR1', 'ADD') }} ; {{ coeff('R0') }} ;;
    {{ coeff('R1') }} ; SET LR2 CR0 ; SET LR10 LR1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.packed }} LR0 ; INC LR4 1 ;;
{% for i in range(k) %}
    {# Load the next activation while consuming the current residual. #}
    {{ pair_mac('LR2', 'ADD') }} {% if i %} ; INC LR2 1 {% endif %} ;;
    {{ pair_mac('LR10', 'ADD') }}
    {%- if i %} ; INC LR10 1 {% endif %}
    {%- if i + 1 < k %} ; LD.MULT.CYCLIC LR4 {{ cr.packed }} LR0 ; INC LR4 1 {% else %} ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 {% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full_ds }}.L {{ cr.qf_out0 }}.L {{ cr.packed }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.packed }} LR0 ;;
    MULT.RC.VE LR7 CR1 0 LR0 {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; ADD LR12 LR12 {{ cr.spatial_row_stride }} ; DEC LR13 1 ; BNE LR13 CR1 pair_row ;;
    SET LR5 LR3 ; ADD LR9 LR11 CR1 ; DEC LR6 1 ; BNE LR6 CR1 pair_channel ;;
    ADD LR8 LR8 {{ cr.batch_stride }} ; DEC LR15 1 ; BNE LR15 CR1 pair_batch ;;
    HALT ;;
{% else %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR8 CR0 ; SET LR15 {{ cr.out0_d0 }} ;;
    DEC LR5 1 ;;
batch:
    SET LR9 CR0 ; SET LR6 {{ cr.n }} ;;
channel:
    SET LR12 LR8 ; SET LR13 {{ cr.in0_d2 }} ;;
row:
{% if tiles > 1 %}
    SET LR7 {{ cr.tile_or_pair_span }} ;;
tile:
{% endif %}
    SET LR11 LR9 ; SET LR4 LR12 ; SET LR14 CR0 ;;
{% if tiles == 1 %}
    INC LR14 {{ chunks }} ; DEC LR11 1 ; DEC LR4 1 ;;
{% else %}
    INC LR14 {{ chunks }} ; DEC LR11 1 ; SUB LR4 LR4 {{ cr.tile_or_pair_span }} ;;
{% endif %}
    {{ bias_row('ADD.FIRST') }}
    {{ bias_row('ADD') }}
chunk:
{% if k <= 32 %}
    {{ coeff('R0') }} ; SET LR2 CR0 ; SET LR3 LR1 ;;
    {{ coeff('R1') }} ;;
    {{ load_input() }} ;;
{% for i in range(k) %}
    {{ mac('LR2', 'ADD') }} {% if i %} ; INC LR2 1 {% endif %} ;;
    {{ mac('LR3', 'ADD') }} {% if i %} ; INC LR3 1 {% endif %} {% if i + 1 < k %} ; {{ load_input() }} {% endif %} ;;
{% endfor %}
{% else %}
    SET LR2 CR0 ; SET LR3 LR1 ;;
{% if k % 128 %}
    BNE LR14 CR1 load_coeff ;;
    SET LR3 CR0 ;;
    INC LR3 {{ k % 128 }} ;;
load_coeff:
{% endif %}
    {{ coeff('R0') }} ;;
    {{ coeff('R1') }} ;;
    {{ load_input() }} ; DEC LR3 1 ;;
reduce:
    {{ mac('LR2', 'ADD') }} ;;
    {{ mac('LR2', 'ADD') }} ; ADD LR2 LR2 LR1 ; BLT.S LR2 LR3 next_scalar ;;
    DEC LR14 1 ; BNE LR14 CR1 chunk ;;
{% endif %}
{% if tiles == 1 %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; ADD LR12 LR12 {{ cr.spatial_row_stride }} ; DEC LR13 1 ; BNE LR13 CR1 row ;;
{% else %}
    BNE LR7 CR1 full_tile ;;
    {{ store(cr.tail_ds) }} ;;
    ADD LR12 LR12 {{ cr.spatial_row_stride }} ; DEC LR13 1 ; BNE LR13 CR1 row ;;
{% endif %}
    ADD LR9 LR11 CR1 ; DEC LR6 1 ; BNE LR6 CR1 channel ;;
    ADD LR8 LR8 {{ cr.batch_stride }} ; DEC LR15 1 ; BNE LR15 CR1 batch ;;
    HALT ;;
{% if tiles > 1 %}
full_tile:
    {{ store(cr.full_ds) }} ; DEC LR7 1 ; B tile ;;
{% endif %}
{% if k > 32 %}
next_scalar:
    {{ load_input() }} ; DEC LR2 127 ; B reduce ;;
{% endif %}
{% endif %}
