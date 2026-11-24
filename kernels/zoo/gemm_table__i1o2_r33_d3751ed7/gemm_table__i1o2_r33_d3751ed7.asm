{# Input address: batch base + row tile + reduction index * tiles.
   LR4 is the row's lane, LR9 its index within the batch. #}
{% macro mac() %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR6 {{ cr.coeff }} LR0 ; ADD LR5 LR5 {{ cr.tiles }} ;;
    MULT.RC.VE LR0 LR4 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR6 1 ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
    INC LR1 1 ;;
{% endfor %}
    SET LR3 CR0 ;;
{% if in0_d1 > 128 %}
    SET LR11 CR0 ;;
    INC LR11 128 ;;
{% endif %}
batch:
    SET LR4 CR0 ; SET LR9 CR0 ; SET LR10 LR3 ;;
matrix_row:
    SET LR6 CR0 ; SET LR7 CR0 ;;
output_block:
    LD.MULT.CYCLIC LR6 {{ cr.coeff }} LR0 ; SET LR5 LR10 ; SET LR8 {{ cr.G }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR6 1 ;;
{% if k >= 16 %}
dot_group:
{% for i in range(16) %}
    {{ mac() }}
{% endfor %}
    DEC LR8 1 ;;
    BNE LR8 CR0 dot_group ;;
{% endif %}
{% for i in range(k % 16) %}
    {{ mac() }}
{% endfor %}
    INC LR7 1 ;;
    BLT.S LR7 {{ cr.O }} full_block ;;
    {{ store(cr.tail) }}
    INC LR9 1 ;;
    INC LR4 1 ;;
    BLT.S LR9 {{ cr.in0_d1 }} next_row ;;
    ADD LR3 LR3 {{ cr.batch_stride }} ;;
    BLT.S LR3 {{ cr.I }} batch ;;
    HALT ;;
next_row:
{% if in0_d1 > 128 %}
    BLT.S LR4 LR11 matrix_row ;;
    SET LR4 CR0 ;;
    INC LR10 1 ;;
{% endif %}
    BNE LR9 CR0 matrix_row ;;
full_block:
    {{ store(cr.full) }}
    BNE LR7 CR0 output_block ;;
