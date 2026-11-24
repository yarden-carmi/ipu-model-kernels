# LR1 and LR3 are the packed row and lane of the site in channel zero.
# LR2 is its top-left output row; LR10 walks channels at fixed row/lane.
site:
    SET LR5 LR2; SET LR6 CR0; SET LR8 CR0;;
phase:
    LD.MULT.CYCLIC LR6 {{ cr.weights }} LR0; SET LR7 CR0;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.dsout }}.L {{ cr.qf_weights }}.L; ACC.ADD.FIRST; INC LR6 1;;
    SET LR10 LR1;;
channel:
    LD.MULT R0 LR10 {{ cr.in0 }};;
    LD.MULT.CYCLIC LR6 {{ cr.weights }} LR0; ADD LR10 LR10 LR14; INC LR7 1;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.dsout }}.L {{ cr.qf_in0 }}.L; ACC.ADD; INC LR6 1; BNE LR7 {{ cr.cin }} channel;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsout }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5;;
    BEQ LR6 {{ cr.weight_end }} next_site; INC LR5 1; INC LR8 1;;
    BNE LR8 {{ cr.kw }} phase;;
    SET LR8 CR0; ADD LR5 LR5 {{ cr.phasejump }}; BEQ LR0 CR0 phase;;
next_site:
    INC LR3 1; ADD LR2 LR2 {{ cr.kw }}; INC LR9 1;;
    BNE LR9 {{ cr.in0_d3 }} site;;
    SET LR9 CR0; INC LR4 1; ADD LR2 LR2 {{ cr.sitejump }};;
    BEQ LR4 {{ cr.height }} done;;
    BNE LR3 LR15 site;;
    SET LR3 CR0; INC LR1 1; BEQ LR0 CR0 site;;
done:
    HALT;;
