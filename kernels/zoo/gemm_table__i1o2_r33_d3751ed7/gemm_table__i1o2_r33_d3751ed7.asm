{# LR3: batch input base; LR4: matrix row's input lane.
   LR5/LR6: input and coefficient cursors; LR7: output block. #}
{% macro mac() %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR6 {{ cr.coeff }} LR0 ; INC LR5 1 ;;
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
batch:
    SET LR4 CR0 ;;
matrix_row:
    SET LR6 CR0 ; SET LR7 CR0 ;;
output_block:
    LD.MULT.CYCLIC LR6 {{ cr.coeff }} LR0 ; SET LR5 LR3 ; SET LR8 {{ cr.G }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR6 1 ;;
{% if k >= 8 %}
dot_group:
{% for i in range(8) %}
    {{ mac() }}
{% endfor %}
    DEC LR8 1 ;;
    BNE LR8 CR0 dot_group ;;
{% endif %}
{% for i in range(k % 8) %}
    {{ mac() }}
{% endfor %}
    INC LR7 1 ;;
    BLT.S LR7 {{ cr.O }} full_block ;;
    {{ store(cr.tail) }}
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.in0_d1 }} matrix_row ;;
    ADD LR3 LR3 {{ cr.in0_d2 }} ;;
    BLT.S LR3 {{ cr.I }} batch ;;
    HALT ;;
full_block:
    {{ store(cr.full) }}
    BNE LR7 CR0 output_block ;;
