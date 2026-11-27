{# Repack the flat CHW view into feature rows with spatial lanes. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; SET LR10 CR0 ; SET LR8 CR0 ;;
    SET LR15 CR0 ; SET LR14 CR0 ; INC LR8 128 ;;
{% for i in range((in0_d1 + 254) // 255) %}
    INC LR15 {{ [255, in0_d1 - 255*i] | min }} ;;
{% endfor %}
    INC LR14 {{ (m + 127) // 128 }} ; SET LR2 CR0 ; SET LR3 CR0 ;;
stage_row:
    SET LR4 CR0 ; SUB LR5 LR0 LR12 ; SET LR13 CR0 ;;
    DEC LR14 1 ; BEQ LR14 CR1 stage_tail ;;
    INC LR13 128 ; B gather ;;
stage_tail:
    INC LR13 {{ (m - 1) % 128 + 1 }} ;;
gather:
    SET LR11 {{ cr.k }} ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
    SUB LR11 LR11 LR7 ;;
    BLT.S LR11 LR13 segment ;;
    SET LR11 LR13 ;;
segment:
    SUB LR13 LR13 LR11 ; ADD LR7 LR7 LR11 ; BEQ LR11 CR1 gather_last ;;
{% macro scatter() %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 7 ;
    INC LR6 {{ (in0_d1 + 127) // 128 }} ; ADD LR5 LR5 LR12
{%- endmacro %}
    DEC LR11 1 ;;
gather_next:
    {{ scatter() }} ; LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR11 1 ; BNE LR11 CR1 gather_next ;;
gather_last:
    {{ scatter() }} ;;
    BNE LR7 {{ cr.k }} gathered ;;
    DEC LR15 1 ; DEC LR8 1 ; SET LR7 CR0 ; BEQ LR15 CR1 next_batch ;;
    BEQ LR8 CR0 next_block ;;
    ADDBI LRD2 1 ; SET LR6 LR10 ; B gathered ;;
next_batch:
{% for i in range((in0_d1 + 254) // 255) %}
    INC LR15 {{ [255, in0_d1 - 255*i] | min }} ;;
{% endfor %}
{% set skip = (k - 1) * ((in0_d1 + 127) // 128) %}
{% for i in range((skip + 254) // 255) %}
    INC LR10 {{ [255, skip - 255*i] | min }} ;;
{% endfor %}
next_block:
    INC LR10 1 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR8 CR0 ; SET LR6 LR10 ;;
    INC LR8 128 ;;
gathered:
    BNE LR13 CR0 gather ;;
    BEQ LR14 CR0 drain_tail ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.stage }} LR1 ;;
    INC LR1 1 ; B stage_row ;;
drain_tail:
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_in0 }}.L {{ cr.stage }} LR1 ;;
    INC LR1 1 ; INC LR14 {{ (m + 127) // 128 }} ;;
    BLT.S LR1 {{ cr.stage_rows }} stage_row ;;

    SET LR9 CR0 ;;
copy:
    LD.MULT R0 LR9 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {% if m <= 128 %}{{ cr.tail }}{% else %}{{ cr.full }}{% endif %}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ;;
    BLT.S LR9 {{ cr.copy_rows }} copy ;;
    DEC LR9 1 ;;
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR10 CR0 ;;
{% for i in range((n + 254) // 255) %}
    INC LR10 {{ [255, n - 255*i] | min }} ;;
{% endfor %}
{% for i in range(5) %}
    {% if i %}INC LR1 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
{% endfor %}

{% macro mac() %}
    MULT.RC.VE LR0 LR6 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR6 1 ; INC LR4 {{ (m + 127) // 128 }}
{%- endmacro %}
{% macro chunk(count, label) %}
    LD.MULT R0 LR5 {{ cr.coeff }} ; SET LR6 CR0 ; SET LR7 CR0 ;;
    LD.MULT.CYCLIC LR4 {{ cr.stage }} LR0 ; INC LR5 1 ; DEC LR6 1 ; INC LR7 {{ count - 3 }} ;;
{{ label }}:
    {{ mac() }} ; LD.MULT.CYCLIC LR4 {{ cr.stage }} LR0 ; BLT.S LR6 LR7 {{ label }} ;;
    {{ mac() }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; INC LR9 1
{%- endmacro %}
{% macro reduce(tag) %}
    SET LR4 LR11 ;;
{% if k > 128 %}
    SET LR8 CR0 ;;
    INC LR8 {{ (k - 1) // 128 }} ;;
groups_{{ tag }}:
    {{ chunk(128, 'reduce_full_' ~ tag) }}
    DEC LR8 1 ; BNE LR8 CR1 groups_{{ tag }} ;;
{% endif %}
    {{ chunk((k - 1) % 128 + 1, 'reduce_last_' ~ tag) }}
{% endmacro %}
channel:
    SET LR3 LR2 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR3 {{ 2 * ((k + 127) // 128) }} ; INC LR12 {{ (m + 127) // 128 }} ;;
block:
    LD.MULT R0 LR3 {{ cr.coeff }} ; SET LR4 LR11 ; SET LR5 LR2 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    {{ reduce('hi') }}
    {{ reduce('lo') }}
    DEC LR12 1 ; INC LR11 1 ; BNE LR12 CR1 full_block ;;
    {{ store(cr.tail) }} ; SET LR2 LR3 ; DEC LR10 1 ; BNE LR10 CR1 next_channel ;;
    HALT ;;
full_block:
    {{ store(cr.full) }} ; B block ;;
next_channel:
    INC LR2 1 ; B channel ;;
