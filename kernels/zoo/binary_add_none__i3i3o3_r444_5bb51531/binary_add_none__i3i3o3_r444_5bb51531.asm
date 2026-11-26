// Store offset advances before AAQ; the input streams each advance after use.
{% macro add_row(mask, next, branch, count=false) %}
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR3 {{ cr.in1 }} ; INC LR1 1 ; INC LR2 1{% if count %} ; DEC LR4 1{% endif %} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1{% if next %} ; LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR3 1{% endif %}{% if branch %} ; {{ branch }}{% endif %} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; DEC LR1 1 ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
group:
    SET LR4 {{ cr.full }} ; BEQ LR0 {{ cr.full }} tail ;;
full_row:
    {{ add_row('CR15.L', true, 'BLT.S LR0 LR4 full_row', true) }}
tail:
    BEQ LR3 {{ cr.last }} final ;;
    {{ add_row(cr.tail ~ '.L', true, 'B group') }}
final:
    {{ add_row(cr.tail ~ '.L', false, '') }}
    HALT ;;
