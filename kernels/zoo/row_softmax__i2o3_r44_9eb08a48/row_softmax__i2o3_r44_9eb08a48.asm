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
pack_tile:
{{ addr('LR12',7) }}
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
unpack_row:
    SET LR4 LR2 ; SET LR12 LR1 ;;
    LD.MULT R0 LR4 {{ cr.transposed }} ; DEC LR12 8 ;;
unpack_chunk:
    SET LR8 LR6 ; SET LR9 LR7 ; SET LR15 CR0 ;;
    INC LR15 16 ;;
unpack_tile:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD10 LRD8 0 ; INC LR4 1 ; DEC LR15 1 ; BLT.S LR12 CR1 unpack_tail ;;
    ADDBI LRD8 8 ; LD.MULT R0 LR4 {{ cr.transposed }} ; DEC LR12 8 ; BNE LR15 CR0 unpack_tile ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.transposed }} LR3 ; INC LR3 1 ; B unpack_chunk ;;
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
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR10 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    SET LR4 LR2 ; SET LR3 CR0 ;;
{% call(ds) tiles('exponentiate') %}
    LD.MULT R0 LR4 {{ cr.transposed }} ;;
{% for slot, reg in coeffs %}
    MULT.RC.VV {{ 'LR10' if loop.first else 'LR0' }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}SUB{% else %}ADD{% endif %}{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE {{ 'LR10' if loop.first else 'LR0' }} LR11 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}ADD{% else %}SUB{% endif %}{% if not loop.last %} ; LD.MULT.CYCLIC {{ coeffs[loop.index][1] }} {{ cr.tmp }} LR0{% endif %} ;;
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
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.exps }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.exps }} LR3 ;;
    LD.MULT R1 LR3 {{ cr.exps }} ;;
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
