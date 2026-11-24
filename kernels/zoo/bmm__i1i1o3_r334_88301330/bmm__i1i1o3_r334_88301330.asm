{# For the upper output, duplicate B so the shifted vector has the
   same row metadata on both sides of the cyclic slot boundary. #}
{% macro mac(vec, first=false) %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
{% if vec == 'LR9' %}
    LD.MULT.CYCLIC LR5 {{ cr.clean_b }} LR0 ;;
{% endif %}
    LD.MULT.CYCLIC LR5 {{ cr.clean_b }} LR8 ;;
    MULT.RC.VE {{ vec }} LR3 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; INC LR5 1 ;;
{% endmacro %}
{% macro reduce(vec, first) %}
    SET LR5 LR1 ;;
    {{ mac(vec, first) }}
    BEQ LR5 LR7 {{ 'low_end' if first else 'high_end' }} ;;
{{ 'low_loop' if first else 'high_loop' }}:
    {{ mac(vec) }}
    BNE LR5 LR7 {{ 'low_loop' if first else 'high_loop' }} ;;
{{ 'low_end' if first else 'high_end' }}:
    INC LR3 1 ; DEC LR2 1 ;;
    BLT.S LR3 {{ cr.m }} {{ 'low_next' if first else 'store' }} ;;
    SET LR3 CR0 ; SET LR1 LR7 ; ADD LR7 LR7 {{ cr.k }} ;;
{% if first %}
low_next:
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ; SET LR7 {{ cr.k }} ; SET LR8 {{ cr.width }} ;;
    SET LR6 CR0 ;;
clean:
    LD.MULT R0 LR6 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.dskey }}.L {{ cr.qf_in1 }}.L {{ cr.clean_b }} LR6 ;;
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.keys }} clean ;;
pair:
    {{ reduce('LR8', true) }}
    BEQ LR2 CR0 store ;;
    {{ reduce('LR9', false) }}
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dspair }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
    BNE LR2 CR0 pair ;;
    HALT ;;
