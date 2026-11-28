{% set uniform = out0_d2 % (128 // out0_d3) == 0 or out0_d2 <= 128 // out0_d3 %}
{% set row_count = out0_d0 * out0_d1 * ((out0_d2 + (128 // out0_d3) - 1) // (128 // out0_d3)) %}
{% if uniform %}
{% set mask = ('CR15' if 128 % out0_d3 == 0 and out0_d2 % (128 // out0_d3) == 0 else (cr.tail_mask if out0_d2 <= 128 // out0_d3 else cr.full_mask)) ~ '.L' %}
{% macro add_first() %}
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ;;
{% endmacro %}
{% macro add_second() %}
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 {{ cr.minus_one }} ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
{% if row_count > 1 %}
fast_row:
    {{ add_first() }}
    {{ add_second() }} ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; BLT.S LR5 {{ cr.fast_limit }} fast_row ;;
{% endif %}
    {{ add_first() }}
    {{ add_second() }} ; HALT ;;
{% else %}
{% macro row(mask) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ; MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; SET LR4 LR1 ; INC LR1 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
{% endmacro %}
    INC LR2 128 ; SET LR3 {{ cr.row_group }} ;;
loop:
    DEC LR3 1 ;;
    BEQ LR3 CR0 tail ;;
    {{ row(cr.full_mask ~ '.L') }}
    B loop ;;
tail:
    {{ row(cr.tail_mask ~ '.L') }}
    SET LR3 {{ cr.row_group }} ; BLT.S LR4 {{ cr.rows }} loop ;;
    HALT ;;
{% endif %}
