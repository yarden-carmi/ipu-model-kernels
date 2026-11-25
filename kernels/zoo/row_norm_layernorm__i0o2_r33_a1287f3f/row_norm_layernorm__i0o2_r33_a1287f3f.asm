{% set iq = cr.qf_in0 ~ '.L' %}
{% set q = cr.qf_gamma ~ '.L' %}
{% set full = 'CR15.L' %}
{% set tail = cr.limits ~ '.L' %}
{% set one = cr.limits ~ '.H' %}
{% macro imm(reg, n) %}
 SET {{ reg }} CR0 ;;
 {% for bit in range(n.bit_length()-1,-1,-1) %}
 {% if not loop.first %} ADD {{ reg }} {{ reg }} {{ reg }} ;; {% endif %}
 {% if (n // (2 ** bit)) % 2 %} INC {{ reg }} 1 ;; {% endif %}
 {% endfor %}
{% endmacro %}
{% macro vec(op, ds=full, src='CR1') %}
 MULT.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}
{% endmacro %}
{% macro store(ds, ptr, act='identity') %}
 ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ q }} {{ cr.tmp }} {{ ptr }}
{% endmacro %}
{% macro split(ds, ptr) %}
 {{ store(ds, ptr) }} ;;
 LD.MULT R0 {{ ptr }} {{ cr.tmp }} ;;
 {{ vec('SUB', ds) }} ; INC {{ ptr }} 1 ; {{ store(ds, ptr) }} ;;
 INC {{ ptr }} 1 ;;
{% endmacro %}
{# A logical (b,t,c) has storage index b + B*t + B*T*c.
   Divide this index by the stored plane size to get the source lane;
   the remainder selects the physical [t,c] row. #}
{% macro gather(label, count, ds) %}
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR9 {{ count }} ;;
{{ label }}:
 LD.MULT R0 LR7 {{ cr.in0 }} ;;
 ADD LR7 LR7 {{ cr.stride }} ;;
 MULT.EE LR8 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 7 ; BLT.S LR7 {{ cr.plane }} {{ label }}_next ;;
 SUB LR7 LR7 {{ cr.plane }} ; INC LR8 1 ;;
{{ label }}_next:
 ADDBI LRD2 1 ; DEC LR9 1 ;;
 BNE LR9 CR0 {{ label }} ;;
 {{ split(ds, 'LR10') }}
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
 {{ imm('LR10',16) }}
 {{ imm('LR12',in0_d0) }}
 {{ imm('LR13',in0_d1) }}
 {{ imm('LR14',channels-128) }}
 {{ imm('LR15',128) }}
batch_loop:
 SET LR5 LR4 ; SET LR6 LR13 ;;
gather_row:
 SET LR7 LR5 ; SET LR8 CR0 ;;
 {# The first element may itself cross a stored plane in a narrow tensor. #}
gather_start:
 BLT.S LR7 {{ cr.plane }} gather_ready ;;
 SUB LR7 LR7 {{ cr.plane }} ; INC LR8 1 ; B gather_start ;;
gather_ready:
 {{ gather('gather_full','LR15',full) }}
 {{ gather('gather_tail','LR14',tail) }}
 ADD LR5 LR5 LR12 ; DEC LR6 1 ;;
 BNE LR6 CR0 gather_row ;;
 INC LR4 1 ;;
 BLT.S LR4 LR12 batch_loop ;;

{# Scratch rows 0:2 mean, 2:6 centered, 6 inv std, 7:9 gain. #}
 SET LR3 CR0 ; SET LR15 CR0 ; SET LR14 CR0 ;;
 INC LR3 128 ; INC LR15 16 ; SET LR13 LR10 ;;
norm_row:
 SET LR5 CR0 ; SET LR4 LR15 ; LD.MULT.CYCLIC LR5 {{ cr.crow }} LR0 ;;
 INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.crow }} LR3 ;;
 LD.MULT R0 LR4 {{ cr.tmp }} ;;
 {% for ds in [full,tail] %}
 {% set first_chunk = loop.first %}
 {% for part in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if first_chunk and part == 0 %}.FIRST{% endif %} LR0 {{ ds }} ;;
 {% if not (part == 1 and not first_chunk) %}INC LR4 1 ; LD.MULT R0 LR4 {{ cr.tmp }} ;{% endif %} MULT.RC.VV LR3 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 {% endfor %}
 SET LR6 CR0 ; {{ split(one,'LR6') }}
 SET LR4 LR15 ; SET LR6 CR0 ;;
 INC LR6 2 ;;
 {% for ds in [full,tail] %}
 LD.MULT R0 LR4 {{ cr.tmp }} ;;
 INC LR4 1 ; LD.MULT R0 LR4 {{ cr.tmp }} ; {{ vec('ADD.FIRST',ds) }} ;;
 INC LR4 1 ; LD.MULT R0 LR0 {{ cr.tmp }} ; {{ vec('ADD',ds) }} ;;
 LD.MULT R0 LR0 {{ cr.tmp }} ; MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
 {# Mean residual is scratch row 1, also selected in R0 at lane zero. #}
 SET LR5 CR1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
 {{ split(ds,'LR6') }}
 {% endfor %}

 SET LR6 CR0 ;;
 INC LR6 2 ;;
 {% for ds in [full,tail] %}
 LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
 INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR3 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 INC LR6 1 ;;
 MULT.RC.VS LR0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if loop.first %}.FIRST{% endif %} LR0 {{ ds }} ;;
 {% for _ in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 MULT.RC.VS LR3 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;
 {% endfor %}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ vec('ADD',one) }} ; {{ store(one,'LR6','rsqrt') }} ;;
 {# Newton correction: with a = sum of squares + epsilon and y the
    hardware rsqrt, keep 2*y and y*(1-a*y*y) as separate factors. #}
 SET LR7 CR0 ;;
 INC LR7 9 ;;
 {{ split(one,'LR7') }}
 LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ one }} {{ q }} ; ACC.ADD.FIRST ;;
 {{ split(one,'LR7') }}
 DEC LR7 2 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
 INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR3 ;;
 SET LR5 CR1 ; LD.MULT R0 LR5 {{ cr.epsilon }} ;;
 {{ vec('ADD.FIRST',one) }} ; DEC LR7 3 ; LD.MULT R0 LR7 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ one }} {{ q }} ; ACC.SUB ;;
 MULT.RC.VV LR3 R0 0 LR0 {{ one }} {{ q }} ; ACC.SUB ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ one }} {{ q }} ; ACC.SUB ;;
 MULT.RC.VV LR3 R0 0 LR0 {{ one }} {{ q }} ; ACC.SUB ; {{ store(one,'LR7') }} ;;
 LD.MULT R0 LR7 {{ cr.tmp }} ;;
 LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ one }} {{ q }} ; ACC.ADD.FIRST ; INC LR7 4 ; {{ store(one,'LR7') }} ;;
 LD.MULT R1 LR6 {{ cr.tmp }} ;;
 SET LR6 CR0 ;;
 INC LR6 2 ;;
 {% for ds in [full,tail] %}
 SET LR5 {{ 'CR0' if loop.first else 'CR1' }} ;;
 LD.MULT.CYCLIC LR5 {{ cr.gamma }} LR0 ;;
 INC LR5 2 ; LD.MULT.CYCLIC LR5 {{ cr.gamma }} LR3 ;;
 MULT.RC.VE LR0 LR3 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
 {% for slot in ['LR0','LR3','LR3'] %}
 MULT.RC.VE {{ slot }} LR3 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 SET LR7 CR0 ;;
 INC LR7 14 ; LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {% for slot in ['LR0','LR3'] %}
 MULT.RC.VE {{ slot }} LR0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 SET LR7 CR0 ;;
 INC LR7 7 ;;
 {{ split(ds,'LR7') }}
 LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
 INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR3 ;;
 INC LR6 1 ;;
 DEC LR7 2 ; LD.MULT R0 LR7 {{ cr.tmp }} ;;
 INC LR7 1 ; LD.MULT R0 LR7 {{ cr.tmp }} ; MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
 DEC LR7 1 ; LD.MULT R0 LR7 {{ cr.tmp }} ; MULT.RC.VV LR3 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
 MULT.RC.VV LR3 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
 SET LR5 {{ 'CR0' if loop.first else 'CR1' }} ; LD.MULT R0 LR5 {{ cr.beta }} ;;
 INC LR5 2 ; LD.MULT R0 LR5 {{ cr.beta }} ; {{ vec('ADD',ds) }} ;;
 {{ vec('ADD',ds) }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ;;
 INC LR14 1 ;;
 {% endfor %}
 INC LR15 4 ;;
 BLT.S LR15 LR13 norm_row ;;
 HALT ;;
