# Project one tile of channel/phase columns into scratch, one row per site.
# LR0 stays zero; LR3 is the tile's weight base, LR5 the output offset,
# and LR6 the number of channels already written.
tile:
    SET LR1 CR0;;
project:
    SET LR2 LR3; LD.MULT R0 LR1 {{ cr.in0 }}; SET LR4 CR0; SET LR13 CR0;;
    LD.MULT.CYCLIC LR2 {{ cr.weights }} LR0; DEC LR13 1;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_weights }}.L; ACC.ADD.FIRST; INC LR2 1; LD.MULT.CYCLIC LR2 {{ cr.weights }} LR0;;
mac:
    INC LR13 1; INC LR2 1; INC LR4 1; MULT.RC.VE LR0 LR13 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L; ACC.ADD; LD.MULT.CYCLIC LR2 {{ cr.weights }} LR0; BNE LR4 {{ cr.mac_end }} mac;;
    INC LR13 1; MULT.RC.VE LR0 LR13 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L; ACC.ADD; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.tile }} LR1;;
    INC LR1 1; INC LR2 1;;
    BNE LR1 {{ cr.sites }} project;;
    SET LR3 LR2; SET LR7 CR0;;

# Transpose the scratch tile into channel-major packed rows. The top two
# bytes of each reshape map select the two horizontal shuffle phases.
channel:
    SET LR1 CR0;;
packed_row:
    SET LR9 LR15; SET LR11 LR15;;
    ADDB LRD8 LR7;;
{% macro gather_row(phase) %}
    SET LR4 CR0;;
gather_{{ phase }}:
    LD.MULT.CYCLIC LR1 {{ cr.tile }} LR0; INC LR4 1;;
    INC LR1 1; MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L; ACC.RESHAPE LRD8 LRD10 6;;
    ADDBI LRD10 2; BNE LR4 {{ cr.in0_d3 }} gather_{{ phase }};;
    {% if phase % 2 == 0 %}
    SUB LR1 LR1 {{ cr.in0_d3 }}; ADDBI LRD8 2;;
    {% elif phase != 3 %}
    ADDBI LRD8 -2;;
    {% endif %}
{% endmacro %}
{% for phase in range(4) %}
    {{ gather_row(phase) }}
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.packed }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5;;
    INC LR5 1; BNE LR1 {{ cr.sites }} packed_row;;
    INC LR6 1; INC LR7 4;;
    BEQ LR6 {{ cr.cout }} done;;
    BNE LR7 {{ cr.lanes }} channel;;
    BEQ LR0 CR0 tile;;
done:
    HALT;;
