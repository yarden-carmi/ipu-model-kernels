{% set q = cr.qf_in0 ~ '.L' %}
{% macro addr(n) %}
 SET LR1 CR0 ;;
 {% if n %}INC LR1 {{ n }} ;;{% endif %}
{% endmacro %}
{% macro load(n, slot=none, base=cr.tmp) %}
 {{ addr(n) }}
 {% if slot %}LD.MULT.CYCLIC LR1 {{ base }} {{ slot }} ;;
 {% else %}LD.MULT R0 LR1 {{ base }} ;;
 {% endif %}
{% endmacro %}
{% macro vec(op='ADD', first=false, imm='CR1') %}
 MULT.VE LR0 {{ imm }} 0 LR0 CR15.L {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro mul(slot='LR0', op='ADD', first=false) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro save(n, parts=3) %}
 {{ addr(n) }}
 {% for i in range(parts) %}
 ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR1 ;;
 {% if not loop.last %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ vec('SUB') }}
 INC LR1 1 ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro scale_sum(src) %}
 {% for i in range(3) %}
 {{ load(i, 'LR0', cr.inv_channels) }}
 {% set first = loop.first %}
 {% for j in range(3) %}
 {{ load(src+j) }}{{ mul(first=first and loop.first) }}
 {% endfor %}
 {% endfor %}
{% endmacro %}
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR7 CR1 ;;
 SET LR3 CR0 ; SET LR4 CR0 ; SET LR12 CR0 ;;
 INC LR3 128 ; INC LR4 128 ; INC LR12 128 ;;
 INC LR4 128 ; INC LR12 255 ;;
 INC LR12 1 ;;
row_loop:
 SET LR5 LR2 ; ADD LR6 LR2 {{ cr.K }} ;;
 {{ vec(first=true, imm='CR0') }}
stats_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
 INC LR5 1 ;;
 BLT.S LR5 LR6 stats_loop ;;
 {{ save(0) }}

 {# Multiply each scalar piece before broadcasting lane zero. #}
 {{ scale_sum(0) }}
 {{ save(21) }}
 {% for j in range(3) %}
 {{ load(21+j) }}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3) }}

 {# Center before squaring to avoid cancellation on nearly constant rows. #}
 SET LR5 LR2 ; SET LR13 CR0 ;;
 INC LR13 24 ;;
center_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 {{ vec(first=true) }}
 {% for j in range(3) %}
 {{ load(3+j) }}{{ vec('SUB') }}
 {% endfor %}
 {% for j in range(3) %}
 ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR13 ;;
 {% if not loop.last %}
 LD.MULT R0 LR13 {{ cr.tmp }} ;;
 {{ vec('SUB') }}
 {% endif %}
 INC LR13 1 ;;
 {% endfor %}
 INC LR5 1 ;;
 BLT.S LR5 LR6 center_loop ;;

 SET LR5 LR2 ; SET LR13 CR0 ;;
 INC LR13 24 ;;
 {{ vec(first=true, imm='CR0') }}
variance_loop:
 SET LR1 LR13 ;;
 {% set slots = ['LR0','LR3','LR4'] %}
 {% for slot in slots %}
 LD.MULT.CYCLIC LR13 {{ cr.tmp }} {{ slot }} ;;
 INC LR13 1 ;;
 {% endfor %}
 {% for j in range(3) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for slot in slots %}
 {% set i = loop.index0 %}
 {% if i <= j %}
 {% for k in range(1 if i == j else 2) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
 {% endfor %}
 {% endif %}
 {% endfor %}
 INC LR1 1 ;;
 {% endfor %}
 INC LR5 1 ;;
 BLT.S LR5 LR6 variance_loop ;;
 {{ save(0) }}
 {{ scale_sum(0) }}
 {{ save(21) }}
 {% for j in range(3) %}
 {{ load(21+j) }}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ vec() }}
 {{ addr(9) }}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(10) }}
 {{ load(9,'LR0') }}{{ load(9) }}{{ mul(first=true) }}
 {{ save(13,2) }}
 {% for i in range(2) %}
 {{ load(13+i,'LR0') }}
 {% set first = loop.first %}
 {% for j in range(3) %}
 {{ load(10+j) }}{{ mul(first=first and loop.first) }}
 {% endfor %}
 {% endfor %}
 {{ save(15,2) }}
 {{ load(9,'LR0') }}
 {% for j in range(3) %}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {% for j in range(2) %}
 {{ load(15+j) }}{{ mul(op='SUB') }}
 {% endfor %}
 {{ save(17,3) }}

 SET LR5 LR2 ; SET LR10 CR0 ; SET LR11 CR0 ;;
 {{ load(3,'LR3') }}{{ load(4,'LR4') }}{{ load(5,'LR12') }}
output_loop:
 {% for i in range(3) %}
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {% set first = loop.first %}
 {% for j in range(3) %}
 {{ load(17+j) }}{{ mul(first=first and loop.first) }}
 {% endfor %}
 INC LR10 1 ;;
 {% endfor %}
 {{ save(20,3) }}
 LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
 {% for i in range(3) %}
 {{ load(20+i) }}{{ mul(first=loop.first) }}
 {% for slot in ['LR3','LR4','LR12'] %}{{ mul(slot, 'SUB') }}{% endfor %}
 {% endfor %}
 {% for i in range(3) %}
 LD.MULT R0 LR11 {{ cr.beta }} ;;
 {{ vec() }}
 INC LR11 1 ;;
 {% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0|default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
 INC LR5 1 ;;
 BLT.S LR5 LR6 output_loop ;;
 SET LR2 LR6 ; BLT.S LR6 {{ cr.M }} row_loop ;;
 HALT ;;
