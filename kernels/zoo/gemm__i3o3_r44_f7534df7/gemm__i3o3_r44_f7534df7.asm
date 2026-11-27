{% macro bias_plane(first) %}
    LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% set pack = [in0_d2, 128 // in0_d3] | min %}
{% macro pixel_row(p) %}
    MULT.RC.VV {{ ['LR7', 'LR1', 'LR3', 'LR13'][p] }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    MULT.RC.VV {{ ['LR7', 'LR1', 'LR3', 'LR13'][p] }} R1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if p + 1 < pack %}; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR7 ; INC LR2 1{% else %}; ADD LR2 LR2 {{ cr.step }} ; DEC LR6 1 ; BNE LR6 CR1 tap{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR14 {{ cr.in0_d0 }} ; DEC LR5 1 ; SET LR7 CR0 ;;
{% if in0_d3 == 32 %}
    INC LR7 128 ; LD.MULT.CYCLIC LR0 {{ cr.in0 }} LR0 ;;
    SET LR1 CR0 ; SET LR3 CR0 ; SET LR13 CR0 ;;
    INC LR1 96 ; INC LR3 64 ; INC LR13 32 ;;
{% endif %}
batch:
    SET LR9 CR0 ; SET LR10 {{ cr.groups }} ;;
group:
    SET LR11 CR0 ; SET LR12 {{ cr.tiles }} ;;
tile:
    SET LR4 LR9 ; SET LR2 LR8 ;;
    ADD LR2 LR2 LR11 ; DEC LR4 1 ;;
{% if in0_d3 == 32 %}    DEC LR2 1 ;;{% endif %}
    {% for p in range(2) %}{{ bias_plane(p == 0) }}{% endfor %}
    SET LR6 {{ cr.k }} {% if in0_d3 != 32 %}; SET LR3 CR0{% endif %} ;;
tap:
{% if in0_d3 == 32 %}
    LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ;;
    LD.MULT R1 LR4 {{ cr.w }} ; INC LR4 1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR7 ; INC LR2 1 ;;
    {% for p in range(pack) %}{{ pixel_row(p) }}{% endfor %}
{% else %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ;;
    MULT.RC.VV LR3 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ;;
    MULT.RC.VV LR3 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR2 LR2 {{ cr.tiles }} ; DEC LR6 1 ; BNE LR6 CR1 tap ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
    INC LR11 {% if in0_d3 == 32 %}{{ pack }}{% else %}1{% endif %} ; DEC LR12 1 ; BNE LR12 CR1 tile ;;
    ADD LR9 LR9 {{ cr.coeffstep }} ; DEC LR10 1 ; BNE LR10 CR1 group ;;
    ADD LR8 LR8 {{ cr.batchstep }} ; DEC LR14 1 ; BNE LR14 CR1 batch ;;
    HALT ;;
