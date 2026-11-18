    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    SET LR4 CR0 ;;
    INC LR4 1 ;;
row:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
{% macro scale_part(base, offset, first) %}
    LD.MULT R0 {{ offset }} {{ base }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ first }} ;;
{% endmacro %}
{{ scale_part(cr.scale, 'LR0', '.FIRST') }}
{{ scale_part(cr.scale_lo, 'LR0', '') }}
{{ scale_part(cr.scale_lo, 'LR4', '') }}
{% macro bias_part(base, offset, qf) %}
    LD.MULT R0 {{ offset }} {{ base }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ qf }}.L ; ACC.ADD ;;
{% endmacro %}
{{ bias_part(cr.bias, 'LR0', cr.qf_bias) }}
{{ bias_part(cr.bias_lo, 'LR0', cr.qf_bias_lo) }}
{{ bias_part(cr.bias_lo, 'LR4', cr.qf_bias_lo) }}
    ACTIVATE.QUANTIZE {{ act_out0 }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR1 1 ;;
    INC LR2 1 ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.count }}.H row ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_bias_lo }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    SET LR3 CR0 ;;
    BLT.S LR1 {{ cr.count }}.L row ;;
    SET LR3 CR0 ;;
    DEC LR3 1 ;;
bottom:
    ACTIVATE.QUANTIZE {{ act_out0 }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.count }}.H bottom ;;
    HALT ;;
