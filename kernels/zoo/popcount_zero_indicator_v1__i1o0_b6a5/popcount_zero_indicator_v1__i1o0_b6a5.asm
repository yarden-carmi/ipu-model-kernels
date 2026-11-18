{# Fixed-address interval predicates with split exact integer boundaries. #}
{% macro bound(subtract) %}
{% for part in range(4) %}
LD.MULT R1 LR2 {{ cr.bounds }};;
MULT.RC.VV LR0 R1 0 LR0 CR15.L {{ cr.qf_bounds }}.L ; ACC.{{ 'SUB' if subtract else 'ADD' }} ; INC LR2 1;;
{% endfor %}
{% endmacro %}
SET LR0 CR0;;
LD.MULT.CYCLIC LR0 {{ cr.gainvec }} LR0;;
SET LR8 CR0;;
INC LR8 128;;
LD.MULT.CYCLIC LR0 {{ cr.gaininput }} LR8;;
SET LR1 CR0;;
SET LR3 CR0;;
tile:
SET LR2 CR0;;
row:
LD.MULT R0 LR1 {{ cr.in0 }};;
MULT.RC.VV LR8 R0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST;;
{{ bound(false) }}
ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf_out0 }}.L {{ cr.lo }} LR0;;
MULT.RC.VV LR8 R0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST;;
{{ bound(true) }}
ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf_out0 }}.L {{ cr.hi }} LR0;;
LD.MULT R0 LR0 {{ cr.ones }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST;;
LD.MULT R0 LR0 {{ cr.lo }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB;;
LD.MULT R0 LR0 {{ cr.hi }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3;;
ADD LR3 LR3 {{ cr.tiles }};;
BLT.S LR2 LR14 row;;
INC LR1 1;;
SET LR3 CR0;;
ADD LR3 LR3 LR1;;
BLT.S LR1 {{ cr.tiles }} tile;;
HALT;;
