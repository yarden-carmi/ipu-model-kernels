{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set vert = cr.vertical ~ '.L' %}
{% macro bias(mode) %}
    LD.MULT R0 LR8 {{ cr.coeff }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ cr.qf_coeff }}.L ; ACC.{{ mode }} ; INC LR8 1 ;;
{% endmacro %}
{% macro mac_strips(scalar) %}
{% for idx in ['LR0', 'LR10', 'LR12'] %}
    MULT.RC.VE {{ idx }} {{ scalar }} 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
{% endfor %}
{% endmacro %}
{% macro spill(residual) %}
    ACTIVATE.QUANTIZE identity {{ vert }} {{ qi }} {{ cr.strips }} LR3 ;;
{% if residual %}
    LD.MULT R0 LR3 {{ cr.strips }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.SUB ; INC LR3 1 ;;
{% else %}
    INC LR3 1 ;;
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 {{ cr.in0_d0 }} ;;
    SET LR10 CR0 ; SET LR11 CR0 ;;
    INC LR10 128 ;;
batch:
    SET LR14 CR0 ; SET LR3 CR0 ;;
transpose_column:
    SET LR6 CR0 ;;
transpose_channel:
    ADD LR15 LR11 LR6 ; SET LR7 {{ cr.in0_d2 }} ; SET LR12 CR0 ;;
    SET LR13 CR0 ;;
transpose_row:
    LD.MULT R0 LR15 {{ cr.in0 }} ;;
    MULT.EE LR14 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.RESHAPE LRD12 LRD12 7 ; ADD LR15 LR15 {{ cr.k }} ; DEC LR7 1 ;;
    ADDBI LRD12 1 ;;
    BNE LR7 CR0 transpose_row ;;
    {# Keep a residual plane so changing the row scale does not discard small values. #}
    {{ spill(true) }}
    {{ spill(true) }}
    {{ spill(false) }}
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.k }} transpose_channel ;;
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.in0_d3 }} transpose_column ;;
    SUB LR11 LR15 LR6 ; SET LR6 {{ cr.n }} ; SET LR9 CR0 ;;
    INC LR11 1 ; SET LR12 LR10 ;;
    INC LR12 128 ;;
output_channel:
    SET LR4 CR0 ; SET LR5 {{ cr.in0_d3 }} ;;
output_column:
    SET LR8 LR9 ; SET LR7 {{ cr.k }} ;;
    {{ bias('ADD.FIRST') }}
    {{ bias('ADD') }}
    {{ bias('ADD') }}
reduce:
    LD.MULT.CYCLIC LR4 {{ cr.strips }} LR0 ;;
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.strips }} LR10 ;;
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.strips }} LR12 ;;
    INC LR4 1 ; LD.MULT R0 LR8 {{ cr.coeff }} ;;
    INC LR8 1 ; LD.MULT R1 LR8 {{ cr.coeff }} ;;
    {{ mac_strips('LR0') }}
    {{ mac_strips('LR10') }}
    INC LR8 1 ; LD.MULT R0 LR8 {{ cr.coeff }} ;;
    {{ mac_strips('LR0') }}
    INC LR8 1 ; DEC LR7 1 ;;
    BNE LR7 CR0 reduce ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ vert }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; DEC LR5 1 ;;
    BNE LR5 CR0 output_column ;;
    SET LR9 LR8 ; DEC LR6 1 ;;
    BNE LR6 CR0 output_channel ;;
    DEC LR2 1 ;;
    BNE LR2 CR0 batch ;;
    HALT ;;
