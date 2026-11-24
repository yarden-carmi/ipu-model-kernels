# Reduce each phase dot product directly into its final width lane.
    INC LR8 128;;
    ADD LR9 LR8 LR8;;
    ADD LR10 LR9 LR8;;
channel:
    LD.MULT R1 LR2 {{ cr.weights }}; SET LR1 CR0;;
    INC LR2 1; LD.MULT.CYCLIC LR2 {{ cr.weights }} LR0;;
    INC LR2 1; LD.MULT.CYCLIC LR2 {{ cr.weights }} LR8;;
    INC LR2 1; LD.MULT.CYCLIC LR2 {{ cr.weights }} LR9;;
    INC LR2 1; LD.MULT.CYCLIC LR2 {{ cr.weights }} LR10;;
    INC LR2 1;;
rows:
{% macro row(phase, left, right) %}
    SET LR3 CR0; SET LR4 CR0; SET LR7 CR0;;
    INC LR4 1;;
x_{{ phase }}:
    LD.MULT R0 LR1 {{ cr.in0 }}; MULT.VE LR8 CR1 0 LR0 {{ cr.dot }}.L {{ cr.qf_weights }}.L; AGG.SUM.FIRST LR3 {{ cr.dot }}.L;;
    MULT.RC.VV {{ left }} R0 0 LR0 {{ cr.dot }}.L {{ cr.qf_in0 }}.L; AGG.SUM LR3 {{ cr.dot }}.L;;
    MULT.VE LR8 CR1 0 LR0 {{ cr.dot }}.L {{ cr.qf_weights }}.L; AGG.SUM.FIRST LR4 {{ cr.dot }}.L;;
    MULT.RC.VV {{ right }} R0 0 LR0 {{ cr.dot }}.L {{ cr.qf_in0 }}.L; AGG.SUM LR4 {{ cr.dot }}.L; INC LR1 1; INC LR7 1;;
    INC LR3 2; INC LR4 2; BNE LR7 {{ cr.in0_d3 }} x_{{ phase }};;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5;;
    INC LR5 1;;
{% endmacro %}
    {{ row(0, 'LR0', 'LR8') }}
    SUB LR1 LR1 {{ cr.in0_d3 }};;
    {{ row(1, 'LR9', 'LR10') }}
    BNE LR1 {{ cr.sites }} rows;;
    INC LR6 1;;
    BNE LR6 {{ cr.cout }} channel;;
    HALT;;
