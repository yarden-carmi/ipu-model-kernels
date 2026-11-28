{% set width = in0_d2 %}
{% set input_chunks = (width + 127) // 128 %}
{% set blocks = (m + 127) // 128 %}
{% set first_blocks = blocks if blocks <= 256 else 256 %}
{% set tail = (m - 1) % 128 + 1 %}
{% set chunks = (k + 127) // 128 %}
{% set segment = 16 if m % 16 == 0 and width % 16 == 0 else 8 %}
{% macro scatter8() %}
    MULT.RC.VE LR7 CR1 0 LR6 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;;
    ADDBI LRD2 8 ; INC LR7 8 ;;
{% endmacro %}

{# Read consecutive spans of the flat NCHW view. The reshape indices are
   constant on the source side and advance by eight on the destination side. #}
    SET LR0 {{ cr.idx_lo }} ; SET LR1 {{ cr.idx_hi }} ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
    SET LR10 CR0 ; SET LR13 CR0 ;;
    INC LR13 128 ;;
stage_feature:
    SET LR9 CR0 ;;
    INC LR9 {{ first_blocks }} ;;
{% if blocks > 256 %}
    INC LR9 {{ blocks - 256 }} ;;
{% endif %}
stage_block:
    SET LR2 {{ cr.idx_lo }} ; SET LR3 {{ cr.idx_hi }} ; SET LR8 CR0 ; BEQ LR9 CR1 stage_tail ;;
    INC LR8 {{ 128 // segment }} ; B stage_segment ;;
stage_tail:
    INC LR8 {{ tail // segment }} ;;
stage_segment:
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR6 ;;
    {% for half in range(segment // 8) %}
    {{ scatter8() }}
    {% endfor %}
    INC LR5 {{ segment }} ; DEC LR8 1 ;;
    BEQ LR5 LR12 next_input_row ;;
    {% if width > 128 %}
    BNE LR7 LR13 segment_end ;;
    SET LR7 CR0 ; INC LR4 1 ; B segment_end ;;
    {% else %}
    B segment_end ;;
    {% endif %}
next_input_row:
    SET LR5 CR0 ; SET LR7 CR0 ; ADD LR4 LR4 LR15 ;;
    BLT.S LR4 {{ cr.ir }} segment_end ;;
    SUB LR4 LR4 {{ cr.ir }} ;;
    INC LR4 {{ input_chunks }} ;;
segment_end:
    BNE LR8 CR0 stage_segment ;;
    BEQ LR9 CR1 store_stage_tail ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.stage }} LR10 ; DEC LR9 1 ;;
    INC LR10 1 ; B stage_block ;;
store_stage_tail:
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_in0 }}.L {{ cr.stage }} LR10 ;;
    INC LR10 1 ; DEC LR11 1 ; BNE LR11 CR1 stage_feature ;;

    SET LR9 CR0 ; SET LR0 CR0 ;;
copy:
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.tail if blocks == 1 else cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ;;
    BLT.S LR9 LR14 copy ;;

{% for i in range(5) %}
    {% if i %}INC LR0 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
{% endfor %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR15 CR0 ;;
    INC LR15 {{ first_blocks }} ;;
{% if blocks > 256 %}
    INC LR15 {{ blocks - 256 }} ;;
{% endif %}
    ADD LR14 LR14 LR14 ; DEC LR9 1 ;;
    DEC LR14 1 ;;

{% macro mac() %}
    MULT.RC.VE LR0 LR6 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR6 1 ; ADD LR4 LR4 LR15
{%- endmacro %}
{% macro chunk(count, label) %}
    LD.MULT R0 LR5 {{ cr.coeff }} ; SET LR6 CR0 ; SET LR7 CR0 ;;
    LD.MULT.CYCLIC LR4 {{ cr.stage }} LR0 ; INC LR5 1 ; DEC LR6 1 {% if count > 3 %}; INC LR7 {{ count - 3 }} {% elif count == 2 %}; DEC LR7 1 {% endif %} ;;
{% if count > 1 %}
{{ label }}:
    {{ mac() }} ; LD.MULT.CYCLIC LR4 {{ cr.stage }} LR0 ; BLT.S LR6 LR7 {{ label }} ;;
{% endif %}
    {{ mac() }} ;;
{% endmacro %}
channel:
    SET LR3 LR2 ; SET LR11 CR0 ; SET LR12 LR15 ;;
    INC LR3 {{ 2 * chunks }} ;;
block:
    LD.MULT R0 LR3 {{ cr.coeff }} ; SET LR4 LR11 ; SET LR5 LR2 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% for part in range(2) %}
{% if part %}
    SET LR4 LR11 ;;
{% endif %}
{% if chunks > 1 %}
    SET LR8 CR0 ;;
    INC LR8 {{ chunks - 1 }} ;;
groups_{{ part }}:
    {{ chunk(128, 'reduce_full_' ~ part) }}
    DEC LR8 1 ; BNE LR8 CR1 groups_{{ part }} ;;
{% endif %}
    {{ chunk((k - 1) % 128 + 1, 'reduce_last_' ~ part) }}
{% endfor %}
    DEC LR12 1 ; INC LR11 1 ; BNE LR12 CR1 full_block ;;
    ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; INC LR9 1 ;;
    SET LR2 LR3 ; BLT.S LR9 LR14 next_channel ;;
    HALT ;;
full_block:
    ACTIVATE.QUANTIZE generic {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; INC LR9 1 ; B block ;;
next_channel:
    INC LR2 1 ; B channel ;;
