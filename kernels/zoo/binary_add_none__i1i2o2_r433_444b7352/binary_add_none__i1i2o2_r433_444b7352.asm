// Cyclic slots 0 and 3 are zero guards around the two loaded channel blocks.
{% macro add_window(base, ptr, qf, acc) %}
    LD.MULT.CYCLIC {{ ptr }} {{ base }} LR1 ; ADD LR12 {{ ptr }} CR1 ;;
    LD.MULT.CYCLIC LR12 {{ base }} LR2 ;;
    MULT.RC.VE LR11 CR1 0 LR0 CR15.L {{ qf }}.L ; {{ acc }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ;;
{% endmacro %}

    SET LR0 CR0 ; INC LR1 128 ; INC LR2 128 ;;
    INC LR2 128 ; SET LR3 LR1 ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
    INC LR3 128 ; MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    INC LR3 128 ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.zero }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.zero }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.zero }} LR3 ;;

phase:
    SET LR4 LR7 ; SET LR9 {{ cr.phase_rows }} ; SET LR10 CR0 ;;
row:
    ADD LR11 LR1 LR10 ; ADD LR13 LR10 LR1 ; DEC LR9 1 ;;
    {{ add_window(cr.in0, 'LR4', cr.qf_in0, 'ACC.ADD.FIRST') }}
    {{ add_window(cr.in1, 'LR5', cr.qf_in1, 'ACC.ADD') }}
    BEQ LR9 CR0 last_row ;;
    SET LR10 LR13 ; BLT.S LR13 {{ cr.out0_d2 }} full_row ;;
    SUB LR10 LR13 {{ cr.out0_d2 }} ; ADD LR4 LR4 {{ cr.patch_step }} ; INC LR5 2 ;;
    BEQ LR10 CR0 full_row ;;
    // Ignore the inactive input lanes even when their encoded bytes are nonzero.
    SUB LR14 LR1 LR10 ;;
clear_tail:
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR14 {{ cr.one }}.L ;;
    INC LR14 1 ;;
    BLT.S LR14 LR1 clear_tail ;;
    // The next record contributes exactly LR10 lanes at the end of this row.
    SET LR11 LR10 ;;
    {{ add_window(cr.in0, 'LR4', cr.qf_in0, 'ACC.ADD') }}
    {{ add_window(cr.in1, 'LR5', cr.qf_in1, 'ACC.ADD') }}
full_row:
    {{ store('CR15') }}
    B row ;;
last_row:
    {{ store(cr.tail) }}
    INC LR5 2 ; INC LR7 2 ; INC LR8 1 ;;
    BLT.S LR8 {{ cr.out0_d0 }} phase ;;
    HALT ;;
