{% macro subtract(src) %}
LD.MULT.CYCLIC LR0 {{ src }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
{% endmacro %}
{% macro scale(partner) %}
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
LD.MULT R0 LR0 {{ partner }} ;;
LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro ramp(upper) %}
LD.MULT R0 LR0 {{ cr.in0 }} ;;
{% if upper %}
ADD LR8 LR2 {{ lr.chunks }} ;;
{% else %}
SET LR8 LR2 ;;
{% endif %}
LD.MULT.CYCLIC LR8 {{ cr.hi }} LR0 ;;
MULT.EE LR1 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_hi }}.L ; ACC.SUB ;;
LD.MULT.CYCLIC LR2 {{ cr.lo }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
{% if upper %}
{{ subtract(cr.ones) }}
{% endif %}
{{ scale(cr.gain) }}
LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
{% for i in range(6) %}
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD ;;
{% endfor %}
ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf_out0 }}.L {% if upper %}{{ cr.tmp }}{% else %}{{ cr.lower }}{% endif %} LR0 ;;
{% endmacro %}
{% macro row(ds) %}
{{ ramp(false) }}
{{ ramp(true) }}
LD.MULT.CYCLIC LR0 {{ cr.lower }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
{{ subtract(cr.tmp) }}
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
{% for i in range(5) %}
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD ;;
{% endfor %}
{{ subtract(cr.tmp) }}
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.ones }} LR14 ;;
LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
MULT.RC.VE LR14 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE relu {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
INC LR2 1 ; INC LR3 1 ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
LD.MULT R0 LR0 {{ cr.in0 }} ;;
SET LR5 CR1 ;;
LD.MULT R1 LR5 {{ cr.in0 }} ;;
token_loop:
SET LR2 CR0 ;;
chunk_loop:
{{ row('CR15.L') }}
ADD LR5 LR2 CR1 ;;
BLT.S LR5 {{ lr.chunks }} chunk_loop ;;
{{ row(cr.lastds ~ '.L') }}
INC LR1 1 ;;
BLT.S LR1 {{ lr.tokens }} token_loop ;;
HALT ;;
