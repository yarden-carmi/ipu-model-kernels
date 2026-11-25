# LR1 = input batch base + y, LR2 = output site, LR3/LR4 = x/y.
# LR5/LR6 = output/weight rows, LR7 = input lane, LR8 = phase x.
# LR9 = channels covered, LR10 = input row, LR11 = y group, LR12 = batch.
# LR13 = packed rows per channel, LR14 = y lane base.
{% macro mac(prefetch) %}
    MULT.RC.VE LR0 LR7 0 LR0 {{ cr.dsout }}.L {{ cr.qf_in0 }}.L; ACC.ADD{% if prefetch %}; INC LR6 1; LD.MULT.CYCLIC LR6 {{ cr.weights }} LR0{% endif %};;
{% endmacro %}
stride:
    INC LR13 1; INC LR15 8;;
    BNE LR15 {{ cr.in0_d2 }} stride;;
site:
    SET LR5 LR2; SET LR6 CR0; SET LR8 CR0;;
    ADD LR7 LR3 LR14;;
phase:
    LD.MULT.CYCLIC LR6 {{ cr.weights }} LR0; SET LR9 CR0; SET LR10 LR1;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.dsout }}.L {{ cr.qf_in0 }}.L; ACC.ADD.FIRST; LD.MULT.CYCLIC LR6 {{ cr.weights }} LR0; INC LR6 1;;
channel:
    LD.MULT R0 LR10 {{ cr.in0 }}; INC LR9 1;;
    BEQ LR9 {{ cr.cin }} last_channel; ADD LR10 LR10 LR13;;
    {{ mac(true) }}
    BEQ LR0 CR0 channel;;
last_channel:
    {{ mac(false) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsout }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5; INC LR6 1;;
    BEQ LR6 {{ cr.weights_end }} next_site; INC LR5 1; INC LR8 1;;
    BNE LR8 {{ cr.kw }} phase;;
    SET LR8 CR0; ADD LR5 LR5 {{ cr.phasejump }}; BEQ LR0 CR0 phase;;
next_site:
    ADD LR2 LR2 {{ cr.kw }}; INC LR3 1;;
    BNE LR3 {{ cr.in0_d3 }} site;;
    SET LR3 CR0; INC LR4 1; INC.MODP2 LR14 {{ cr.in0_d3 }} 7;;
    BEQ LR4 {{ cr.in0_d2 }} next_batch; ADD LR2 LR2 {{ cr.sitejump }};;
    BNE LR14 CR0 site;;
    INC LR11 1; INC LR1 1; BEQ LR0 CR0 site;;
next_batch:
    SET LR4 CR0; INC LR12 1; SUB LR1 LR10 LR11;;
    SET LR11 CR0;;
    BNE LR12 {{ cr.in0_d0 }} site;;
    HALT;;
