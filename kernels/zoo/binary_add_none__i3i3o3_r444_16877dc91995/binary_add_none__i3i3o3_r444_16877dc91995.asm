{% macro add_row(mask) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ;;
plane:
    SET LR2 {{ cr.pitch }} ;;
row:
    BEQ LR2 CR1 tail ;;
    {{ add_row(cr.full ~ '.L') }}
    INC LR1 1 ; DEC LR2 1 ; B row ;;
tail:
    {{ add_row(cr.tail ~ '.L') }}
    INC LR1 1 ; DEC LR3 1 ;;
    BNE LR3 CR0 plane ;;
    HALT ;;
