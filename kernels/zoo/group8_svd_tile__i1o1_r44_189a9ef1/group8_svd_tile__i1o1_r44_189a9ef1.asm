{% set ds = cr.full ~ '.L' %}
{% set q = cr.qf_in0 ~ '.L' %}
{% macro load(slot) %}LD.MULT.CYCLIC LR5 {{ cr.coeff }} {{ slot }} ; INC LR5 1{% endmacro %}
{% macro prod(slot, scalar, op='ADD') %}MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}{% endmacro %}
{% macro project_step(prefetch) %}
    {{ prod('LR0', 'LR7') }} ; {{ load('LR12') }} ; INC LR7 1 ;;
    {{ prod('LR12', 'LR7') }} {% if prefetch %}; {{ load('LR0') }} ; BLT.S LR7 LR14 project {% endif %} ;;
{% endmacro %}
{% macro phase(p) %}
    SET LR6 CR0 ; SET LR8 {{ cr.groups }} ; SET LR13 CR0 ;;
    {{ load('LR0') }} ;;
    {{ prod('LR0', 'CR1', 'ADD.FIRST') }} ; {{ load('LR12') }} ;;
    {{ prod('LR12', 'CR1') }} ;;
phase_{{p}}_group:
    LD.MULT R0 LR6 {{ cr.latent }} ; SET LR7 LR13 ; SET LR11 LR13 ;;
    LD.MULT R1 LR6 {{ cr.latent }} ; INC LR6 1 ; INC LR11 127 ; ADD LR14 LR13 {{ cr.rank }} ;;
    DEC LR14 1 ; DEC LR7 1 ;;
phase_{{p}}_rank:
    {{ load('LR0') }} ; INC LR7 1 ; INC LR11 1 ;;
    {{ prod('LR0', 'LR7') }} ; {{ load('LR12') }} ;;
    {{ prod('LR0', 'LR11') }} ;;
    {{ prod('LR12', 'LR7') }} ;;
    {{ prod('LR12', 'LR11') }} ; BLT.S LR7 LR14 phase_{{p}}_rank ;;
    ADD LR13 LR13 {{ cr.rank }} ; DEC LR8 1 ;;
    BEQ LR8 CR0 phase_{{p}}_store ;;
    SET LR9 {{ cr.span }} ;;
    BLT.S LR13 LR9 phase_{{p}}_same ;;
    INC LR6 1 ; SET LR13 CR0 ; BEQ LR0 CR0 phase_{{p}}_group ;;
phase_{{p}}_same:
    DEC LR6 1 ; BEQ LR0 CR0 phase_{{p}}_group ;;
phase_{{p}}_store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 {{ cr.height }} ; SET LR12 CR0 ; SET LR15 {{ cr.in0_d3 }} ;;
    INC LR12 128 ; ADD LR15 LR15 {{ cr.in0_d3 }} ;;
row:
    SET LR3 {{ cr.in0_d3 }} ;;
site:
    LD.MULT R0 LR1 {{ cr.in0 }} ; SET LR5 CR0 ; SET LR6 CR0 ; SET LR8 {{ cr.blocks }} ;;
    DEC LR5 1 ;;
project_block:
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ; SET LR7 CR0 ; SET LR14 {{ cr.cin }} ;;
    DEC LR14 1 ; DEC LR7 1 ; {{ load('LR0') }} ;;
    BEQ LR14 CR0 project_last ;;
    DEC LR14 1 ;;
project:
    {{ project_step(true) }}
project_last:
    {{ project_step(false) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.latent }} LR6 ;;
    LD.MULT.CYCLIC LR6 {{ cr.latent }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; INC LR6 1 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.latent }} LR6 ;;
    INC LR6 1 ; DEC LR8 1 ;;
    BNE LR8 CR0 project_block ;;

    SET LR10 LR2 ;;
    {{ phase(0) }}
    INC LR10 1 ;;
    {{ phase(1) }}
    ADD LR10 LR2 LR15 ;;
    {{ phase(2) }}
    INC LR10 1 ;;
    {{ phase(3) }}
    INC LR1 1 ; INC LR2 2 ; DEC LR3 1 ;;
    BNE LR3 CR0 site ;;
    ADD LR2 LR2 LR15 ; DEC LR4 1 ;;
    BNE LR4 CR0 row ;;
    HALT ;;
