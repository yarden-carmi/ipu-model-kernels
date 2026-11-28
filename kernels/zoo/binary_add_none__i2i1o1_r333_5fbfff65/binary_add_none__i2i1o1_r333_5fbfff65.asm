{% if out0_d1 % 128 == 0 and out0_d0 * out0_d2 * (out0_d1 // 128) > 1 %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR13 ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
fast_row:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; BLT.S LR5 {{ cr.fast_limit }} fast_row ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; HALT ;;
{% else %}
{% macro add_row(mask, full_row=false) %}
    MULT.VE LR4 CR1 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} {% if full_row %}; SET LR7 LR1 {% endif %};;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} {{ 'LR7' if full_row else 'LR1' }} {% if full_row %}; INC LR1 1 ; INC LR2 1 ; DEC LR3 1 ; B row {% endif %};;
{% endmacro %}
    SET LR3 {{ cr.width }} ; INC LR6 128 ;;
row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR7 LR2 CR1 ; BEQ LR3 CR1 tail ;;
    BEQ LR4 CR0 full ;;
    LD.MULT R1 LR7 {{ cr.in0 }} ;;
full:
    {{ add_row('CR15.L', true) }}
tail:
    ADD LR5 LR4 {{ cr.valid }} ;;
    BGE.S LR6 LR5 tail_ready ;;
    LD.MULT R1 LR7 {{ cr.in0 }} ;;
tail_ready:
    {{ add_row(cr.tail ~ '.L') }}
    INC LR1 1 ; SET LR3 {{ cr.width }} ; SET LR4 LR5 ;;
    BEQ LR1 {{ cr.rows }} finish ;;
    BLT.S LR4 LR6 row ;;
    DEC LR4 128 ; INC LR2 1 ; B row ;;
finish:
    HALT ;;
{% endif %}
