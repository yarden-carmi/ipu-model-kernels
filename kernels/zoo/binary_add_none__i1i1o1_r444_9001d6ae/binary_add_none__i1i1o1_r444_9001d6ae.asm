{% macro product(start, qf, acc) %}
    MULT.VE {{ start }} CR1 0 LR0 {{ cr.full }}.L {{ qf }}.L ; {{ acc }}
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5
{%- endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR6 CR1 ; SET LR7 {{ cr.shifted }} ;;
    BGE.S LR5 {{ cr.pairs }} tail ;;
pair:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    {{ product('LR0', cr.qf_in0, 'ACC.ADD.FIRST') }} ; LD.MULT R1 LR6 {{ cr.in0 }} ;;
    # The slice crosses from the padding of R0 to the data of R1.
    {{ product('LR7', cr.qf_in0, 'ACC.ADD') }} ; LD.MULT R0 LR4 {{ cr.in1 }} ;;
    {{ product('LR0', cr.qf_in1, 'ACC.ADD') }} ; LD.MULT R1 LR6 {{ cr.in1 }} ;;
    {{ product('LR7', cr.qf_in1, 'ACC.ADD') }} ; {{ store(cr.full) }} ;;
    INC LR4 2 ; INC LR6 2 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.pairs }} pair ;;
tail:
    BGE.S LR5 {{ cr.out_rows }} done ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    {{ product('LR0', cr.qf_in0, 'ACC.ADD.FIRST') }} ; LD.MULT R0 LR4 {{ cr.in1 }} ;;
    {{ product('LR0', cr.qf_in1, 'ACC.ADD') }} ; {{ store(cr.tail) }} ;;
done:
    HALT ;;
