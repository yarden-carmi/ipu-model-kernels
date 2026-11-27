{% macro add_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR4 {{ cr.in1 }} ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR1 1 ; INC LR4 1 ;;
{% endmacro %}
    INC LR2 128 ;;
batch:
    SET LR5 CR0 ;;
position:
    SET LR3 {{ cr.blocks }} ;;
block:
    DEC LR3 1 ;;
    BEQ LR3 CR0 tail ;;
    {{ add_row('CR15.L') }}
    BEQ LR0 CR0 block ;;
tail:
    {{ add_row(cr.tail ~ '.L') }}
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.out0_d1 }} position ;;
    SET LR7 {{ cr.skip }} ;;
    BEQ LR7 CR0 batch_end ;;
    SET LR7 CR0 ;;
padding:
    LD.MULT R1 LR4 {{ cr.in1 }} ;;
    MULT.VE LR2 CR0 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.zero }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.skip }} padding ;;
batch_end:
    INC LR6 1 ;;
    BLT.S LR6 LR15 batch ;;
    HALT ;;
