# Duplicate each width-lane value into the two horizontal phases. This
# preserves the row maximum and thus the input's quantization grid.
input_y:
    SET LR2 CR0;;
duplicate_channel:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0; SET LR4 CR0; SET LR9 CR0; SET LR11 LR15;;
duplicate_x:
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L; ACC.RESHAPE LRD8 LRD10 6; INC LR4 1;;
    ADDBI LRD8 1; ADDBI LRD10 2; BNE LR4 {{ cr.in0_d3 }} duplicate_x;;
    ACTIVATE.QUANTIZE identity {{ cr.width }}.L {{ cr.qf_in0 }}.L {{ cr.tile }} LR2; INC LR1 1;;
    INC LR2 1;;
    BNE LR2 {{ cr.cin }} duplicate_channel;;
    SET LR3 CR0;;
output_row:
    LD.MULT.CYCLIC LR3 {{ cr.weights }} LR0; SET LR2 CR0;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.width }}.L {{ cr.qf_weights }}.L; ACC.ADD.FIRST; INC LR3 1;;
mac:
    LD.MULT.CYCLIC LR2 {{ cr.tile }} LR0;;
    LD.MULT R0 LR3 {{ cr.weights }}; INC LR2 1;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L; ACC.ADD; INC LR3 1; BNE LR2 {{ cr.cin }} mac;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5;;
    INC LR5 1; BNE LR3 {{ cr.weight_end }} output_row;;
    BNE LR1 {{ cr.input_rows }} input_y;;
    HALT;;
