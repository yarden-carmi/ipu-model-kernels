{% set q = cr.qf_in0 ~ '.L' %}
{% set root = cr.rootq ~ '.L' %}
{% set full = cr.active ~ '.L' %}
{% set part = cr.part ~ '.L' %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro addr(reg, val) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ val }} ;;
{% endmacro %}
{% macro tiles(label) %}
    SET LR7 CR0 ;;
    BEQ LR7 LR8 {{ label }}_tail ;;
{{ label }}_full:
{{ caller(full) }}
    INC LR7 1 ;;
    BLT.S LR7 LR8 {{ label }}_full ;;
{{ label }}_tail:
{{ caller(part) }}
{% endmacro %}

{# Factor a full tile's transpose through groups of 16 columns by 8 rows.
   Each intermediate row holds 16 input rows, with 8 lanes from each. #}
    BNE LR1 CR0 transpose_edges ;;
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR12 LR4 ; SET LR13 LR5 ; SET LR14 CR0 ;;
    SET LR15 CR0 ;;
{% macro pack16(i) %}
    LD.MULT R0 LR4 {{ cr.in0 }}{% if i > 0 %} ; ADDBI LRD8 1{% endif %} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD6 LRD8 0 ; ADD LR4 LR4 {{ cr.pitch }} ;;
{% endmacro %}
full_tile:
    SET LR1 CR0 ; SET LR5 CR0 ;;
pack_group:
    SET LR6 LR10 ; SET LR7 LR11 ;;
pack_row:
    SET LR4 LR2 ; SET LR8 LR12 ; SET LR9 LR13 ;;
{% for i in range(16) %}{{ pack16(i) }}{% endfor %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    INC.MODP2 LR1 CR1 7 ; INC.MODP2 LR5 CR1 4 ; ADDBI LRD6 8 ;;
    BNE LR5 CR0 pack_row ;;
    SET LR2 LR4 ; BNE LR1 CR0 pack_group ;;

{% macro unpack16(i) %}
    LD.MULT R0 LR4 {{ cr.tmp }}{% if i > 0 %} ; ADDBI LRD6 -8 ; ADDBI LRD8 8{% endif %} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD6 LRD8 0 ; INC LR4 16 ;;
    ADDBI LRD6 8 ; ADDBI LRD8 8 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD6 LRD8 0 ;;
{% endmacro %}
unpack_group:
    SET LR6 LR10 ; SET LR7 LR11 ; SET LR5 CR0 ;;
unpack_row:
    SET LR4 LR1 ; SET LR8 LR10 ; SET LR9 LR11 ;;
{% for i in range(8) %}{{ unpack16(i) }}{% endfor %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.transposed }} LR3 ;;
    ADD LR3 LR3 {{ cr.K }} ; INC.MODP2 LR5 CR1 3 ; ADDBI LRD6 8 ;;
    BNE LR5 CR0 unpack_row ;;
    INC.MODP2 LR1 CR1 4 ;;
    BNE LR1 CR0 unpack_group ;;
    {# LR3 advanced by 128*K. #}
    SET LR4 {{ cr.K }} ;;
{% for i in range(7) %}
    ADD LR4 LR4 LR4 ;;
{% endfor %}
    INC LR15 1 ;;
    BEQ LR15 {{ cr.K }} full_next_row_tile ;;
    SUB LR3 LR3 LR4 ;;
    INC LR3 1 ; B full_tile ;;
full_next_row_tile:
    SUB LR3 LR3 {{ cr.K }} ;;
    INC LR3 1 ; SET LR15 CR0 ; INC LR14 1 ;;
    BGE.S LR3 {{ cr.M }} transpose_done ;;
    BEQ LR14 {{ cr.pitch }} full_next_batch ;;
    SUB LR2 LR2 {{ cr.batchstride }} ;;
    INC LR2 1 ; B full_tile ;;
full_next_batch:
    SUB LR2 LR2 {{ cr.pitch }} ; SET LR14 CR0 ;;
    INC LR2 1 ; B full_tile ;;

{# Partial tiles use the direct gather to avoid reading padding as data. #}
transpose_edges:
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
{{ addr('LR11',128) }}
transpose_batch:
    SET LR5 CR0 ; SET LR9 CR0 ; SET LR10 CR0 ;;
transpose_row:
    ADD LR4 LR2 LR10 ; SET LR8 {{ cr.K }} ;;
transpose_tile:
    DEC LR8 1 ; SET LR6 CR0 ; SET LR7 CR0 ;;
    SET LR1 LR11 ;;
    BNE LR8 CR0 gather_first ;;
    SET LR1 LR12 ;;
{% macro scatter() %}MULT.EE LR9 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD6 LRD6 7{% endmacro %}
gather_first:
    LD.MULT R0 LR4 {{ cr.in0 }} ; DEC LR1 1 ; BEQ LR1 CR1 gather_single ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ; {{ scatter() }} ; ADD LR4 LR4 {{ cr.pitch }} ; DEC LR1 1 ; BEQ LR1 CR1 gather_last ;;
gather_next:
    LD.MULT R0 LR4 {{ cr.in0 }} ; {{ scatter() }} ; ADD LR4 LR4 {{ cr.pitch }} ; DEC LR1 1 ; ADDBI LRD6 1 ; BNE LR1 CR1 gather_next ;;
gather_last:
    ADDBI LRD6 1 ;;
gather_single:
    {{ scatter() }} ; ADD LR4 LR4 {{ cr.pitch }} ;;
    BEQ LR8 CR0 transpose_tail ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.transposed }} LR3 ;;
    INC LR3 1 ;;
    B transpose_tile ;;
transpose_tail:
    ACTIVATE.QUANTIZE identity {{ part }} {{ q }} {{ cr.transposed }} LR3 ;;
    INC LR3 1 ; INC LR5 1 ; INC LR9 1 ;;
    BEQ LR5 LR14 transpose_next ;;
    BNE LR9 LR11 transpose_row ;;
    SET LR9 CR0 ; INC LR10 1 ;;
    B transpose_row ;;
transpose_next:
    ADD LR2 LR2 {{ cr.batchstride }} ; DEC LR15 1 ;;
    BNE LR15 CR0 transpose_batch ;;
transpose_done:

{# Generate split log2(e)/2 and the root scaling without folded constants. #}
{% macro coefficient(power, count, slot) %}
{{ addr('LR1',7) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ addr('LR6',power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ slot }} ;;
{{ addr('LR1',slot) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ addr('LR6',count) }}
numerator_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 numerator_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}
{{ addr('LR11',128) }}
    SET LR10 LR11 ; SET LR12 LR11 ;;
    INC LR12 128 ;;
    SET LR13 LR12 ;;
    INC LR13 128 ;;
{{ addr('LR1',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% for p,c,s in [(5,23,5),(13,21,6),(19,18,8),(26,19,9)] %}
{{ coefficient(p,c,s) }}
{% endfor %}
{{ coefficient(16,1,10) }}
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ root }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
{{ coefficient(94,1,11) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ root }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR13 ;;
    SET LR8 {{ cr.K }} ; SET LR2 CR0 ;;
    DEC LR8 1 ;;
row:
    SET LR4 LR2 ;;
{{ clear() }}
    LD.MULT R0 LR4 {{ cr.transposed }} ;;
    BEQ LR8 CR0 max_single ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ;;
    SET LR7 CR0 ;;
max_next:
    INC LR4 1 ;;
    LD.MULT R0 LR4 {{ cr.transposed }} ; INC LR7 1 ;;
    BEQ LR7 LR8 max_tail ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ;;
    B max_next ;;
max_tail:
    MULT.VE LR0 CR1 0 LR0 {{ part }} {{ q }} ; AGG.MAX LR0 {{ part }} ;;
    B max_ready ;;
max_single:
    MULT.VE LR0 CR1 0 LR0 {{ part }} {{ q }} ; AGG.MAX.FIRST LR0 {{ part }} ;;
max_ready:
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    SET LR4 LR2 ; SET LR3 CR0 ;;
{% call(ds) tiles('exponentiate') %}
    LD.MULT R0 LR4 {{ cr.transposed }} ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{% for slot in [5,6,8,9] %}
{{ addr('LR5',slot) }}
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}SUB{% else %}ADD{% endif %}{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}ADD{% else %}SUB{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.roots }} ;;
    MULT.RC.VV LR12 R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.roots }} LR3 ;;
    INC LR4 1 ; INC LR3 1 ;;
{% endcall %}
    SET LR3 CR0 ;;
{{ clear() }}
{% call(ds) tiles('sum') %}
    LD.MULT R0 LR3 {{ cr.roots }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ root }} ; AGG.SUM LR0 {{ ds }} ;;
    INC LR3 1 ;;
{% endcall %}
{# Preserve the sum and reciprocal as high and residual pieces. #}
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.EE LR11 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
    SET LR1 CR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
{{ addr('LR5',7) }}
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR10 LR0 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
    MULT.RC.VE LR10 LR11 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
    INC LR1 2 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    SET LR3 CR0 ; SET LR4 LR2 ;;
{% call(ds) tiles('normalize') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VE LR13 CR1 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD ;;
    MULT.RC.VE LR13 CR1 0 LR0 {{ ds }} {{ root }} ; ACC.SUB ;;
{{ addr('LR5',12) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR5 ;;
    LD.MULT R1 LR5 {{ cr.tmp }} ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR3 1 ; INC LR4 1 ;;
{% endcall %}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row ;;
    HALT ;;
