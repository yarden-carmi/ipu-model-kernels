{#- Square each lane, replacing the previous accumulator with the self-product. -#}
{% macro square(ds) %}
LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0;;
LD.MULT R0 LR1 {{ cr.in0 }};;
MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1;;
INC LR1 1;;
{% endmacro %}

SET LR0 CR0 ; SET LR1 CR0;;
row_loop:
{% if in0_d1 % 128 == 0 %}
{{ square('CR15.L') }}
{% else %}
{% if in0_d1 >= 128 %}
SET LR2 CR0;;
full_loop:
{{ square('CR15.L') }}
INC LR2 1;;
BLT.S LR2 {{ cr.full }} full_loop;;
{% endif %}
{{ square(cr.tail_ds ~ '.L') }}
{% endif %}
BLT.S LR1 {{ cr.rows }} row_loop;;
HALT;;
