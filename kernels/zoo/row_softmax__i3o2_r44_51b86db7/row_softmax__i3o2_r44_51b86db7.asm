{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set qr = cr.scratch_qf ~ '.L' %}
{% set qw = cr.scratch_qf ~ '.H' %}
{% set qp = cr.plane_qf ~ '.L' %}
{% set qe = cr.plane_qf ~ '.H' %}
{% set qt = cr.final_qf ~ '.L' %}
{% set full = cr.active ~ '.L' %}
{% set part = cr.part ~ '.L' %}
{% set out = cr.outpart ~ '.L' %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro addr(reg, value) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ value }} ;;
{% endmacro %}
{% macro coefficient(power, numerator, slot) %}
{{ addr('LR1',7) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ addr('LR6',power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qr }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ slot }} ;;
{{ addr('LR1',slot) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qr }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ addr('LR6',numerator) }}
numerator_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qr }} ; ACC.ADD ; DEC LR6 1 ;;
    BNE LR6 CR0 numerator_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}
{% macro scale() %}
{% for idx in [5,6,8,9] %}
{{ addr('LR5',idx) }}
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR9 ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ part }} {{ q }} ; ACC.{% if loop.last %}SUB{% else %}ADD{% endif %}{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE LR9 LR11 0 LR0 {{ part }} {{ q }} ; ACC.{% if loop.last %}ADD{% else %}SUB{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro gather_lanes(label) %}
    SET LR4 LR9 ;;
    SET LR1 CR0 ;;
    SET LR12 CR0 ;;
    SET LR13 CR0 ;;
{{ clear() }}
{{ label }}:
    LD.MULT R0 LR4 {{ cr.norm }} ;;
    MULT.EE LR10 CR1 0 LR0 {{ full }} {{ qp }} ; ACC.RESHAPE LRD12 LRD12 7 ;;
    INC LR4 1 ; ADDBI LRD12 1 ; INC LR1 1 ;;
    BLT.S LR1 LR14 {{ label }} ;;
{% endmacro %}
    SET LR0 CR0 ;;
{{ addr('LR11',128) }}
    SET LR9 CR0 ;;
    SET LR10 LR11 ;;

{# Build log2(e) from dyadic terms without folded constants. #}
{{ addr('LR1',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qr }} {{ cr.tmp }} LR1 ;;
{% for p,k,s in [(4,23,5),(12,21,6),(18,18,8),(25,19,9)] %}
{{ coefficient(p,k,s) }}
{% endfor %}

    SET LR2 CR0 ;;
row:
{{ clear() }}
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ part }} {{ q }} ; AGG.MAX.FIRST LR0 {{ part }} ;;
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{{ scale() }}
{# The common shift cancels in the normalization. #}
{{ addr('LR5',5) }}
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR9 ;;
    MULT.RC.VE LR9 CR1 0 LR0 {{ part }} {{ q }} ; ACC.SUB ;;
{{ addr('LR3',13) }}
    ACTIVATE.QUANTIZE exp2 {{ part }} {{ qe }} {{ cr.tmp }} LR3 ;;
    SET LR5 LR2 ;;
{% for plane in range(3) %}
    ACTIVATE.QUANTIZE identity {{ part }} {{ qp }} {{ cr.norm }} LR5 ;;
{% if not loop.last %}
    LD.MULT R0 LR5 {{ cr.norm }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ part }} {{ qp }} ; ACC.SUB ; ADD LR5 LR5 {{ cr.rows }} ;;
{% endif %}
{% endfor %}
    ADD LR5 LR5 {{ cr.rows }} ;;

{{ clear() }}
    LD.MULT.CYCLIC LR3 {{ cr.tmp }} LR9 ;;
    MULT.RC.VE LR9 CR1 0 LR0 {{ part }} {{ qe }} ; AGG.SUM.FIRST LR0 {{ part }} ;;
{# Correct the reciprocal for rounding in both the sum and its inverse. #}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qw }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qw }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ qw }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ qw }} ; ACC.ADD.FIRST ;;
    MULT.EE LR11 CR1 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ qw }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
{{ addr('LR4',7) }}
    LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR9 ;;
    MULT.RC.VE LR9 CR1 0 LR0 {{ full }} {{ qr }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR10 LR0 0 LR0 {{ full }} {{ qw }} ; ACC.SUB ;;
    MULT.RC.VE LR10 LR11 0 LR0 {{ full }} {{ qw }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ qw }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ full }} {{ qw }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR10 CR1 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ qp }} {{ cr.norm }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.norm }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qp }} ; ACC.SUB ; ADD LR5 LR5 {{ cr.rows }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ qp }} {{ cr.norm }} LR5 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.rows }} row ;;

{# Gather the two denominator planes once per batch and reuse them across columns. #}
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
{{ addr('LR7',2) }}
transpose_batch:
    SET LR9 LR2 ;;
{% for plane in range(3) %}
    ADD LR9 LR9 {{ cr.rows }} ;;
{% endfor %}
{{ addr('LR6',8) }}
    SET LR10 CR0 ;;
denom_gather:
{{ gather_lanes('denom_lane') }}
    ACTIVATE.QUANTIZE identity {{ out }} {{ qt }} {{ cr.tmp }} LR6 ;;
    ADD LR9 LR9 {{ cr.rows }} ; INC LR6 1 ;;
{{ addr('LR4',10) }}
    BLT.S LR6 LR4 denom_gather ;;
    SET LR10 CR0 ;;
transpose_column:
    SET LR9 LR2 ;;
    SET LR6 CR0 ;;
gather:
{{ gather_lanes('transpose_lane') }}
    BEQ LR6 LR7 gather_finish ;;
    ACTIVATE.QUANTIZE identity {{ out }} {{ qp }} {{ cr.tmp }} LR6 ;;
    ADD LR9 LR9 {{ cr.rows }} ; INC LR6 1 ;;
    B gather ;;
gather_finish:
{% for plane in [1,0] %}
    SET LR6 CR{{ plane }} ;;
    LD.MULT R0 LR6 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ out }} {{ qp }} ; ACC.ADD ;;
{% endfor %}
{{ addr('LR5',10) }}
{# Exponentiate in the consumer layout to use its row scale. #}
    ACTIVATE.QUANTIZE exp2 {{ out }} {{ qt }} {{ cr.tmp }} LR5 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
{% for index in [8,9] %}
{{ addr('LR5',index) }}
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ out }} {{ qt }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ out }} {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; INC LR10 1 ;;
    BLT.S LR10 LR15 transpose_column ;;
    ADD LR2 LR2 LR14 ;;
    BLT.S LR2 {{ cr.rows }} transpose_batch ;;
    HALT ;;
