{% macro sum_row() %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR4 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}
{% macro add_pair(base, qf, acc) %}
    LD.MULT R0 LR4 {{ base }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ qf }}.L ; {{ acc }} ; LD.MULT R1 LR6 {{ base }} ;;
    MULT.VE LR2 CR1 0 LR0 {{ cr.full }}.L {{ qf }}.L ; ACC.ADD ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR2 {{ cr.odd_start }} ;;
    BGE.S LR5 {{ cr.pairs }} tail ;;
pair:
    ADD LR6 LR4 CR1 ;;
    // The cross-register read uses padding encoded in the same format as the odd row.
    {{ add_pair(cr.in0, cr.qf_in0, 'ACC.ADD.FIRST') }}
    {{ add_pair(cr.in1, cr.qf_in1, 'ACC.ADD') }}
    {{ store(cr.full) }}
    INC LR4 2 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.pairs }} pair ;;
tail:
    BGE.S LR4 {{ cr.rows }} done ;;
    {{ sum_row() }}
    {{ store(cr.half) }}
done:
    HALT ;;
