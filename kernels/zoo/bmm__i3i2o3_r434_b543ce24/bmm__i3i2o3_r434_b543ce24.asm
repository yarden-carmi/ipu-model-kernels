{% set chunks = (k+127)//128 %}
{% macro gather(c) %}
    SET LR9 CR0 ; SET LR15 CR0 ;;
    INC LR15 {{ 128 if k-128*c >= 128 else k-128*c }} ;;
gather_{{ c }}:
    LD.MULT R0 LR8 {{ cr.vbase }} ;;
    MULT.EE LR10 CR1 0 LR0 {{ cr.emit }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR9 {{ cr.emit }}.H ;;
    INC LR9 1 ; ADD LR8 LR8 {{ cr.brows }} ;;
    BLT.S LR9 LR15 gather_{{ c }} ;;
    ACTIVATE.QUANTIZE identity {{ cr.dots }}.{{ 'L' if c==0 else 'H' }} {{ cr.qf_in1 }}.L {{ cr.panel }} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}
{% macro dot(c) %}
    LD.MULT R0 LR7 {{ cr.panel }} ;;
    MULT.RC.VV {{ 'LR0' if c==0 else 'LR12' }} R0 0 LR0 {{ cr.dots }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if c==0 else '' }} LR9 {{ cr.dots }}.{{ 'L' if c==0 else 'H' }} ;;
    INC LR7 1 ;
    MULT.RC.VV {{ 'LR13' if c==0 else 'LR14' }} R0 0 LR0 {{ cr.dots }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if c==0 else '' }} LR10 {{ cr.dots }}.{{ 'L' if c==0 else 'H' }} ;;
{% endmacro %}
    INC LR14 128 ;;
    INC LR14 128 ;;
    INC LR14 128 ;;
group:
    SET LR2 LR1 ; SET LR3 {{ cr.lane }} ; SET LR4 {{ cr.head_pairs }}.L ;;
head:
    SET LR7 CR0 ; SET LR10 LR3 ; SET LR12 CR0 ;;
    SET LR13 LR2 ;;
    INC LR12 {{ n }} ;;
column:
    SET LR8 LR13 ;;
{% for c in range(chunks) %}
    {{ gather(c) }}
{% endfor %}
    INC LR10 1 ; DEC LR12 1 ;;
    BEQ LR12 CR0 panel_ready ;;
    SET LR15 CR0 ;;
    INC LR15 128 ;;
    BLT.S LR10 LR15 column ;;
    DEC LR10 128 ; INC LR13 1 ; B column ;;
panel_ready:
    INC LR12 128 ; SET LR11 {{ cr.head_pairs }}.H ; SET LR13 CR0 ;;
    INC LR13 128 ;;
    INC LR13 128 ;;
pair:
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
{% if chunks == 2 %}
    INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR12 ;;
{% endif %}
    INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR13 ;;
{% if chunks == 2 %}
    INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR14 ;;
{% endif %}
    INC LR5 1 ; SET LR7 CR0 ; SET LR9 CR0 ;;
    SET LR10 CR0 ;;
    SET LR15 CR0 ;;
    INC LR10 {{ n }} ; INC LR15 {{ 2*n }} ;;
dot_column:
{% for c in range(chunks) %}
    {{ dot(c) }}
{% endfor %}
    INC LR9 1 ; INC LR10 1 ;;
    BLT.S LR10 LR15 dot_column ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.emit }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; DEC LR11 1 ;;
    BNE LR11 CR0 pair ;;
    DEC LR4 1 ;;
    BEQ LR4 CR0 next_group ;;
    INC LR3 {{ n }} ;;
    BLT.S LR3 LR12 head ;;
    DEC LR3 128 ; INC LR2 1 ; B head ;;
next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.total_rows }} group ;;
    HALT ;;
