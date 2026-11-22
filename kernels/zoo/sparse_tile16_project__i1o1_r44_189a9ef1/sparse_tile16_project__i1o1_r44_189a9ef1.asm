# LR0: zero and cyclic slot; LR1/LR2: input site and output top-left.
# LR3/LR4: x/y counters. LR5: phase-store row; LR6: constant row.
# LR7: input channel; LR8: horizontal phase.
{% macro mac(prefetch) %}
    MULT.RC.VE LR0 LR7 0 LR0 {{ cr.dsout }}.L {{ cr.qf_in0 }}.L; ACC.ADD; INC LR7 1{% if prefetch %}; INC LR6 1; LD.MULT.CYCLIC LR6 {{ cr.weights }} LR0{% endif %};;
{% endmacro %}
site:
    LD.MULT R0 LR1 {{ cr.in0 }}; SET LR5 LR2; SET LR6 CR0; SET LR8 CR0;;
phase:
    LD.MULT.CYCLIC LR6 {{ cr.weights }} LR0; SET LR7 CR0; SET LR9 CR0;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.dsout }}.L {{ cr.qf_weights }}.L; ACC.ADD.FIRST; LD.MULT.CYCLIC LR6 {{ cr.weights }} LR0; INC LR6 1; DEC LR7 1;;
channel:
    INC LR9 16;;
{% for _ in range(15) %}
    {{ mac(true) }}
{% endfor %}
    BEQ LR9 {{ cr.cin }} last_channel;;
    {{ mac(true) }}
    BEQ LR0 CR0 channel;;
last_channel:
    {{ mac(false) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsout }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5; INC LR6 1;;
    BEQ LR6 {{ cr.weights_end }} next_site; INC LR5 1; INC LR8 1;;
    BNE LR8 {{ cr.kw }} phase;;
    SET LR8 CR0; ADD LR5 LR5 {{ cr.phasejump }}; BEQ LR0 CR0 phase;;
next_site:
    INC LR1 1; ADD LR2 LR2 {{ cr.kw }}; INC LR3 1;;
    BNE LR3 {{ cr.in0_d3 }} site;;
    SET LR3 CR0; INC LR4 1; ADD LR2 LR2 {{ cr.sitejump }};;
    BNE LR4 {{ cr.height }} site;;
    HALT;;
