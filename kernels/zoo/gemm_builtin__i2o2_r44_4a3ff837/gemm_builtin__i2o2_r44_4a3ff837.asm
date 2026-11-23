{# A vector is a vertical strip. Each output channel reuses the input
   strips at this column without a spatial transpose. #}
{% macro coeff_load() %}
    INC LR8 1 ;;
    LD.MULT R0 LR8 {{ cr.coeff }} ;;
{% endmacro %}
{% macro bias_add(acc) %}
    {{ coeff_load() }}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_coeff }}.L ; {{ acc }} ;;
{% endmacro %}
{% macro weight_add() %}
    {{ coeff_load() }}
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% endmacro %}
{% macro store(ds) %}
    INC LR3 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    DEC LR3 1 ;;
column:
    SET LR4 CR0 ; SET LR9 CR0 ;;
    DEC LR9 1 ;;
output_channel:
    SET LR6 CR0 ;;
strip:
    ADD LR5 LR1 LR6 ; SET LR8 LR9 ; SET LR7 CR0 ;;
    {{ bias_add('ACC.ADD.FIRST') }}
    {{ bias_add('ACC.ADD') }}
input_channel:
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
    {{ weight_add() }}
    {{ weight_add() }}
    ADD LR5 LR5 {{ cr.chunks }} ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.k }} input_channel ;;
    BEQ LR6 {{ cr.last_chunk }} last_strip ;;
    {{ store(cr.full) }}
    INC LR6 1 ; B strip ;;
last_strip:
    {{ store(cr.tail) }}
    SET LR9 LR8 ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.n }} output_channel ;;
    ADD LR1 LR1 {{ cr.pitch }} ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.pixels }} column ;;
    HALT ;;
