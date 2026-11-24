{% set full = cr.tail ~ '.H' %}
{% macro add_first() %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;
{% endmacro %}
{% macro add_store(ds) %}
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ;;
{% if in0_d2 % 128 == 0 %}
    // Load the next in0 row while adding and storing the current row.
    DEC LR1 1 ; SET LR4 CR0 ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
{% if in0_d0 * in0_d1 * (in0_d2 // 128) > 1 %}
dense:
    {{ add_first() }} INC LR1 1 ; INC LR4 1 ; LD.MULT R1 LR1 {{ cr.in1 }} ;;
    {{ add_store(full) }} LD.MULT R0 LR4 {{ cr.in0 }} ; BLT.S LR4 {{ cr.last_row }} dense ;;
{% endif %}
    {{ add_first() }} INC LR1 1 ; LD.MULT R1 LR1 {{ cr.in1 }} ;;
    {{ add_store(full) }} HALT ;;
{% else %}
    SET LR3 CR0 ;;
padded:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ add_first() }} LD.MULT R1 LR1 {{ cr.in1 }} ; BLT.S LR3 {{ cr.last_chunk }} full_chunk ;;
    {{ add_store(cr.tail ~ '.L') }} SET LR3 CR0 ; B advance ;;
full_chunk:
    {{ add_store(full) }} INC LR3 1 ;;
advance:
    INC LR1 1 ; BLT.S LR1 {{ cr.last_row }} padded ;;
    HALT ;;
{% endif %}
