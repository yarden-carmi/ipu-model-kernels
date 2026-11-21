{% macro add_row(ds) %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; INC LR4 1 ;;
{% endmacro %}

    INC LR2 128 ;;
// For patch phase p and position j, input spatial index is j * phases + p.
// LR6 is the first input row of the phase; LR4 walks its channel blocks.
position:
    SET LR3 {{ cr.blocks }} ;;
block:
    DEC LR3 1 ;;
    BEQ LR3 CR0 tail ;;
    {{ add_row('CR15.L') }}
    BEQ LR0 CR0 block ;;
tail:
    {{ add_row(cr.tail ~ '.L') }}
    INC LR7 1 ; ADD LR4 LR4 {{ cr.patch_skip }} ;;
    BLT.S LR7 {{ cr.out0_d1 }} position ;;
    SET LR7 CR0 ; ADD LR6 LR6 {{ cr.blocks }} ;;
    SET LR4 LR6 ; BLT.S LR1 {{ cr.rows }} position ;;
    HALT ;;
