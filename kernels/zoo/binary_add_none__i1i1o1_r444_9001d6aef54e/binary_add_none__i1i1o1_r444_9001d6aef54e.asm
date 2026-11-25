{% macro accumulate(start, qf, ds, acc='ACC.ADD') %}
    MULT.VE {{ start }} CR1 0 LR0 {{ ds }}.L {{ qf }}.L ; {{ acc }}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR2 {{ cr.odd_start }} ; DEC LR5 1 ; BGE.S LR4 {{ cr.paired_rows }} tail ;;
pair:
    ADD LR6 LR4 CR1 ; INC LR5 1 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
    // Read the odd row across the register boundary, preceded by zero padding.
    {{ accumulate('LR0', cr.qf_in0, cr.full, 'ACC.ADD.FIRST') }} ; LD.MULT R1 LR6 {{ cr.in0 }} ;;
    {{ accumulate('LR2', cr.qf_in0, cr.full) }} ; LD.MULT R0 LR4 {{ cr.in1 }} ;;
    {{ accumulate('LR0', cr.qf_in1, cr.full) }} ; LD.MULT R1 LR6 {{ cr.in1 }} ; INC LR4 2 ;;
    {{ accumulate('LR2', cr.qf_in1, cr.full) }} ; {{ store(cr.full) }} ; BLT.S LR4 {{ cr.paired_rows }} pair ;;
tail:
    INC LR5 1 ; BGE.S LR4 {{ cr.rows }} done ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    {{ accumulate('LR0', cr.qf_in0, cr.half, 'ACC.ADD.FIRST') }} ; LD.MULT R0 LR4 {{ cr.in1 }} ;;
    {{ accumulate('LR0', cr.qf_in1, cr.half) }} ; {{ store(cr.half) }} ;;
done:
    HALT ;;
