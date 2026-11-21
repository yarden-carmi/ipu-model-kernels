{% macro term(coefficient, acc, ds) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro compute(ds) %}
    {{ term(cr.fp_hi, 'ADD.FIRST', ds) }}
    {{ term(cr.fp_hi_base, 'SUB', ds) }}
    {{ term(cr.fp_lo, 'ADD', ds) }}
    {{ term(cr.fp_lo_base, 'SUB', ds) }}
    {{ term(cr.nx_hi, 'ADD', ds) }}
    {{ term(cr.nx_lo, 'ADD', ds) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
batch:
    SET LR3 CR0 ;;
channel:
    SET LR4 CR0 ;;
row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR4 1 ;;
    BEQ LR4 LR6 tail ;;
    {{ compute(cr.ds_pair ~ '.H') }}
    INC LR1 1 ; INC LR2 1 ; INC LR3 1 ;;
    B row ;;
tail:
    {{ compute(cr.ds_pair ~ '.L') }}
    INC LR1 1 ; INC LR2 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.active_rows }} channel ;;
    ADD LR2 LR2 {{ cr.skip }} ;;
    BLT.S LR1 {{ cr.rows }} batch ;;
    HALT ;;
