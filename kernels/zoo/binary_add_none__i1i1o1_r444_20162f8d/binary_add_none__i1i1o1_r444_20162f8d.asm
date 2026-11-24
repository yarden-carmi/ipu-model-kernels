{% macro product(start, qf, acc) %}
    MULT.VE {{ start }} CR1 0 LR0 {{ cr.active }}.L {{ qf }}.L ; {{ acc }}
{%- endmacro %}
{% macro store() %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5
{%- endmacro %}
{% macro first_item() %}
    LD.MULT R0 LR4 {{ cr.in1 }} ;;
    {{ product('LR0', cr.qf_in1, 'ACC.ADD.FIRST') }} ; LD.MULT R1 LR5 {{ cr.in0 }} ;;
    {{ product('LR1', cr.qf_in0, 'ACC.ADD') }} ; {{ store() }} ;;
{%- endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR1 {{ cr.r1_start }} ; SET LR2 {{ cr.in1_d1 }} ;;
    BGE.S LR4 {{ cr.pairs }} tail ;;
pair:
    {{ first_item() }}
    INC LR5 1 ;;
    # Keep the packed row in R0 and start the second sum at its second lane group.
    {{ product('LR2', cr.qf_in1, 'ACC.ADD.FIRST') }} ; LD.MULT R1 LR5 {{ cr.in0 }} ;;
    {{ product('LR1', cr.qf_in0, 'ACC.ADD') }} ; {{ store() }} ;;
    INC LR5 1 ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.pairs }} pair ;;
tail:
    BGE.S LR5 {{ cr.rows }} done ;;
    {{ first_item() }}
done:
    HALT ;;
