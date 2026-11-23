{% set q = cr.qf_in0 ~ '.L' %}
{% set root = cr.rootq ~ '.L' %}
{% set full = cr.active ~ '.L' %}
{% set part = cr.part ~ '.L' %}
{% macro zero() %}MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST{% endmacro %}
{% macro clear() %}    {{ zero() }} ;;{% endmacro %}
{% macro addr(reg, val) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ val }} ;;
{% endmacro %}
{% macro tiles(label, setup='') %}
    {{ setup }}SET LR7 CR1 ; BEQ LR8 CR0 {{ label }}_tail ;;
{{ label }}_full:
{{ caller(full) }}
    INC LR7 1 ; BLT.S LR7 LR8 {{ label }}_full ;;
{{ label }}_tail:
{{ caller(part) }}
{% endmacro %}

{# Tile the transpose through 8x8 blocks. Each input load contributes eight
   logical rows, and each tile load contributes eight columns to one row.
   Load one ahead while advancing the reshape descriptor; the tail branches
   before that load so neither pass reads past its final column. #}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 {{ cr.M }} ;;
    LD.MULT R0 LR0 {{ cr.in0 }} ; DEC LR3 1 ;;
{{ clear() }}
pack_batch:
    SET LR5 LR14 ; SET LR10 CR0 ;;
pack_group:
    SET LR4 LR2 ; SET LR11 LR1 ;;
    SET LR8 LR6 ; SET LR9 LR7 ; SUB LR12 LR0 LR10 ;;
    ADDB LRD8 LR12 ; LD.MULT R0 LR4 {{ cr.in0 }} ; DEC LR11 1 ;;
{{ addr('LR12',7) }}
pack_tile:
    BLT.S LR11 LR12 pack_partial ;;
{% for i in range(7) %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD6 LRD8 0 ; LD.MULT R0 LR4 {{ cr.in0 }} ; ADD LR4 LR4 {{ cr.pitch }}{% if not loop.first %} ; ADDBI LRD8 8{% endif %} ; DEC LR11 1 ;;
{% endfor %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD6 LRD8 0 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.transposed }} LR3 ; ADDBI LRD8 8 ; INC LR3 1 ; BEQ LR11 CR0 pack_group_done ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ; ADD LR4 LR4 {{ cr.pitch }} ; ADDBI LRD8 -56 ; DEC LR11 1 ; B pack_tile ;;
pack_partial:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD6 LRD8 0 ; BEQ LR11 CR0 pack_tail ;;
    ADDBI LRD8 8 ; LD.MULT R0 LR4 {{ cr.in0 }} ; DEC LR11 1 ; ADD LR4 LR4 {{ cr.pitch }} ; B pack_partial ;;
pack_tail:
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.transposed }} LR3 ; INC LR3 1 ;;
pack_group_done:
    DEC LR5 8 ;;
    BLT.S LR5 CR1 pack_next ;;
    INC LR10 8 ; ADDBI LRD6 8 ;;
{{ addr('LR12',128) }}
    BLT.S LR10 LR12 pack_group ;;
    INC LR2 1 ; SUB LR10 LR0 LR10 ;;
    ADDB LRD6 LR10 ;;
    SET LR10 CR0 ; B pack_group ;;
pack_next:
    SUB LR10 LR0 LR10 ; ADD LR2 LR2 LR13 ;;
    ADDB LRD6 LR10 ; BLT.S LR2 LR15 pack_batch ;;

    SET LR2 {{ cr.M }} ; SET LR3 CR0 ;;
    DEC LR3 1 ;;
unpack_batch:
    SET LR5 LR14 ;;
unpack_group:
    ADD LR10 LR6 LR6 ; ADD LR11 LR7 LR7 ;;
{% for i in range(2) %}
    ADD LR10 LR10 LR10 ; ADD LR11 LR11 LR11 ;;
{% endfor %}
{{ addr('LR13',8) }}
{{ addr('LR15',120) }}
unpack_row:
    SET LR4 LR2 ; SET LR12 LR1 ;;
    LD.MULT R0 LR4 {{ cr.transposed }} ; DEC LR12 8 ;;
unpack_chunk:
    SET LR8 LR6 ; SET LR9 LR7 ; BLT.S LR12 LR15 unpack_tile ;;
    DEC LR12 120 ;;
{# The LR increment selects the next tile for LOAD; MULT still sees the old R0. #}
{% for i in range(15) %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD10 LRD8 0 ; LD.MULT R0 LR4 {{ cr.transposed }} ; INC LR4 1{% if not loop.first %} ; ADDBI LRD8 8{% endif %} ;;
{% endfor %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD10 LRD8 0 ; INC LR4 1 ; ADDBI LRD8 8 ; BLT.S LR12 CR1 unpack_tail ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.transposed }} LR3 ; INC LR3 1 ; DEC LR12 8 ;;
    LD.MULT R0 LR4 {{ cr.transposed }} ; B unpack_chunk ;;
unpack_tile:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD10 LRD8 0 ; INC LR4 1 ; BLT.S LR12 CR1 unpack_tail ;;
    ADDBI LRD8 8 ; LD.MULT R0 LR4 {{ cr.transposed }} ; DEC LR12 8 ; B unpack_tile ;;
unpack_tail:
    ACTIVATE.QUANTIZE identity {{ part }} {{ q }} {{ cr.transposed }} LR3 ; INC LR3 1 ; DEC LR5 1 ; ADDBI LRD10 1 ;;
    BEQ LR5 CR0 unpack_next ;;
    DEC LR13 1 ; BNE LR13 CR1 unpack_row ;;
    SET LR2 LR4 ; B unpack_group ;;
unpack_next:
    SET LR2 LR4 ; SET LR4 LR3 ;;
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.M }} unpack_batch ;;

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
{% set coeffs = [(5, 'LR6'), (6, 'LR9'), (8, 'LR14'), (9, 'LR15')] %}
{% for slot, reg in coeffs %}
{{ addr(reg, slot) }}
{% endfor %}
    SET LR8 {{ cr.K }} ; SET LR2 CR0 ;;
    DEC LR8 1 ;;
    BEQ LR8 CR1 pair_row ;;
row:
    {{ zero() }} ; LD.MULT R0 LR2 {{ cr.transposed }} ; SET LR4 LR2 ; SET LR7 CR1 ; SET LR1 CR1 ; BEQ LR8 CR0 max_single ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.transposed }} ;;
max_next:
    BEQ LR7 LR8 max_tail ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ; INC LR4 1 ; INC LR7 1 ; LD.MULT R0 LR4 {{ cr.transposed }} ; B max_next ;;
{% macro max_finish(first) %}
    MULT.VE LR0 CR1 0 LR0 {{ part }} {{ q }} ; AGG.MAX{{ first }} LR0 {{ part }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR10 ; SET LR4 LR2 ; SET LR3 CR0
{%- endmacro %}
max_tail:
    {{ max_finish('') }} ; B max_ready ;;
max_single:
    {{ max_finish('.FIRST') }} ;;
max_ready:
{% macro exponent(ds, setup='') %}
    LD.MULT R0 LR4 {{ cr.transposed }} {{ setup }} ;;
{% for slot, reg in coeffs %}
    MULT.RC.VV {{ 'LR10' if loop.first else 'LR0' }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}SUB{% else %}ADD{% endif %}{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE {{ 'LR10' if loop.first else 'LR0' }} LR11 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}ADD ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3{% else %}SUB ; LD.MULT.CYCLIC {{ coeffs[loop.index][1] }} {{ cr.tmp }} LR0{% endif %} ;;
{% endfor %}
    LD.MULT R0 LR3 {{ cr.roots }} ;;
    MULT.RC.VV LR12 R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.roots }} LR3 ; INC LR4 1 ;;
{% endmacro %}
{% call(ds) tiles('exponentiate', 'LD.MULT R1 LR1 ' ~ cr.tmp ~ ' ; ') %}
    {{ exponent(ds) }}
    INC LR3 1 ;;
{% endcall %}
    {{ zero() }} ; SET LR3 CR0 ;;
{% call(ds) tiles('sum') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; AGG.SUM LR0 {{ ds }} ; INC LR3 1 ;;
{% endcall %}
{# Preserve the sum and reciprocal as high and residual pieces. #}
{% macro inverse() %}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R1 LR1 {{ cr.tmp }} ; SET LR5 CR0 ;;
    MULT.EE LR11 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR1 1 ; ACTIVATE.QUANTIZE reciprocal {{ full }} {{ q }} {{ cr.tmp }} LR1 ; INC LR5 7 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ; INC LR1 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR10 LR0 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
    MULT.RC.VE LR10 LR11 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; SET LR3 CR0 ; SET LR4 LR2 ;;
{% endmacro %}
{% macro normalize(ds, finish='') %}
    MULT.RC.VE LR13 CR1 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD ;;
    MULT.RC.VE LR13 CR1 0 LR0 {{ ds }} {{ root }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.exps }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.exps }} LR3 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.exps }} ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ; INC LR3 1 ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 {{ finish }} ;;
{% endmacro %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
    {{ inverse() }}
{% call(ds) tiles('normalize') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    {{ normalize(ds) }}
    INC LR4 1 ;;
{% endcall %}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row ;;
    HALT ;;

{# Two chunks: unroll all three passes and overlap independent loads with
   the preceding reduction or store. The second chunk can be partial. #}
pair_row:
    {{ zero() }} ; LD.MULT R0 LR2 {{ cr.transposed }} ; SET LR4 LR2 ; SET LR1 CR1 ; SET LR3 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.transposed }} ;;
    {{ max_finish('') }} ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    {{ exponent(full) }}
    {{ exponent(part, '; INC LR3 1') }}
    {{ zero() }} ; SET LR3 CR0 ; LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ full }} {{ root }} ; AGG.SUM LR0 {{ full }} ; INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ part }} {{ root }} ; AGG.SUM LR0 {{ part }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
    {{ inverse() }}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    {{ normalize(full, '; LD.MULT.CYCLIC LR3 ' ~ cr.roots ~ ' LR0') }}
    INC LR4 1 ;;
    {{ normalize(part) }}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} pair_row ;;
    HALT ;;
