{% macro sum_row() %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR4 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}
{% macro accumulate(start, qf, acc='ACC.ADD') %}
    MULT.VE {{ start }} CR1 0 LR0 {{ cr.full }}.L {{ qf }}.L ; {{ acc }}
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR2 {{ cr.odd_start }} ; DEC LR5 1 ; BGE.S LR4 {{ cr.paired_rows }} tail ;;
pair:
    ADD LR6 LR4 CR1 ; INC LR5 1 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
    // The cross-register read uses padding encoded in the same format as the odd row.
    {{ accumulate('LR0', cr.qf_in0, 'ACC.ADD.FIRST') }} ; LD.MULT R1 LR6 {{ cr.in0 }} ;;
    {{ accumulate('LR2', cr.qf_in0) }} ; LD.MULT R0 LR4 {{ cr.in1 }} ;;
    {{ accumulate('LR0', cr.qf_in1) }} ; LD.MULT R1 LR6 {{ cr.in1 }} ; INC LR4 2 ;;
    {{ accumulate('LR2', cr.qf_in1) }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; BLT.S LR4 {{ cr.paired_rows }} pair ;;
tail:
    INC LR5 1 ; BGE.S LR4 {{ cr.rows }} done ;;
    {{ sum_row() }}
    {{ store(cr.half) }}
done:
    HALT ;;
