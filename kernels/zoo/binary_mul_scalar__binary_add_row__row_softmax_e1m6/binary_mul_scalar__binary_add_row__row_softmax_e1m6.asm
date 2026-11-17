{% macro split(start, cyclic=false) %}
{% for j in range(3) %}
 SET LR1 CR0 ;;
 INC LR1 {{ start+j }} ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.poly }} LR1 ;;
{% if cyclic %}
 LD.MULT.CYCLIC LR1 {{ cr.poly }} {{ ['LR0','LR9','LR10'][j] }} ;;
{% endif %}
{% if j < 2 %}
 LD.MULT R0 LR1 {{ cr.poly }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro product() %}
{% for j in range(3) %}
 SET LR1 CR0 ;;
 INC LR1 {{ 3+j }} ;;
 LD.MULT R0 LR1 {{ cr.poly }} ;;
{% for k in range(3) %}
 MULT.RC.VV {{ ['LR0','LR9','LR10'][k] }} R0 0 LR0 CR15.L {{ cr.qf }}.L ; {{ 'ACC.ADD.FIRST' if j==0 and k==0 else 'ACC.ADD' }} ;;
{% endfor %}
{% endfor %}
{% endmacro %}
 SET LR0 CR0 ;;
 SET LR2 CR0 ;;
 SET LR7 CR0 ;;
 SET LR9 CR0 ;;
 INC LR9 128 ;;
 SET LR10 LR9 ;;
 INC LR10 128 ;;
row:
 SET LR3 CR0 ;;
exp_loop:
 LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
 LD.MULT R0 LR0 {{ cr.operand0 }} ;;
 MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 LD.MULT R0 LR7 {{ cr.operand1 }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ split(0, true) }}
 LD.MULT R0 LR0 {{ cr.c5 }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for coeff in ['c4','c3','c2','one','one'] %}
{{ split(3) }}
{{ product() }}
{% if coeff == 'one' %}
 SET LR1 CR0 ;;
 INC LR1 7 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% else %}
 LD.MULT R0 LR0 {{ cr[coeff] }} ;;
{% endif %}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
{% for square in range(8) %}
{{ split(3, true) }}
{{ product() }}
{% endfor %}
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.exps }} LR3 ;;
 LD.MULT R0 LR3 {{ cr.exps }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 SET LR5 LR3 ;;
 INC LR5 2 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.exps }} LR5 ;;
 INC LR2 1 ;;
 INC LR7 1 ;;
 BLT.S LR7 LR8 operand_ready ;;
 SET LR7 CR0 ;;
operand_ready:
 INC LR3 1 ;;
 SET LR4 CR0 ;;
 INC LR4 2 ;;
 BLT.S LR3 LR4 exp_loop ;;
 INC LR4 2 ;;
 SET LR3 CR0 ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
sum_loop:
 LD.MULT R0 LR3 {{ cr.exps }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
 INC LR3 1 ;;
 BLT.S LR3 LR4 sum_loop ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR0 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 SET LR1 CR1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 LD.MULT R1 LR1 {{ cr.tmp }} ;;
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE reciprocal CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 SET LR1 CR0 ;;
 INC LR1 7 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in [3,4] %}
 SET LR1 CR0 ;;
 INC LR1 {{ j }} ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR9 ;;
 DEC LR4 2 ;;
 SET LR3 CR0 ;;
 SET LR5 LR2 ;;
 DEC LR5 2 ;;
out_loop:
 LD.MULT R0 LR3 {{ cr.exps }} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VV LR9 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 SET LR6 LR3 ;;
 INC LR6 2 ;;
 LD.MULT R0 LR6 {{ cr.exps }} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 MULT.RC.VV LR9 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR5 ;;
 INC LR5 1 ;;
 INC LR3 1 ;;
 BLT.S LR3 LR4 out_loop ;;
 BLT.S LR2 {{ cr.M }} row ;;
 HALT ;;
