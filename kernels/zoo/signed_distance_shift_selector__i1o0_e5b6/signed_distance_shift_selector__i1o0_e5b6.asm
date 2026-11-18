{# Fixed-address scan of truncation intervals; tokens occupy lanes. #}
{% macro mul(src, qf, acc='ADD.FIRST') %}
MULT.VE {{ src }} CR1 0 LR0 {{ cr.full_ds }}.L {{ qf }}.L ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro rc(acc='ADD.FIRST') %}
MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.tmp_qf }}.L ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro store(fn, idx) %}
ACTIVATE.QUANTIZE {{ fn }} {{ cr.full_ds }}.L {{ cr.tmp_qf }}.L {{ cr.tmp }} {{ idx }} ;;
{% endmacro %}
{% macro step(dst) %}
{{ store('relu6', 'LR3') }}
LD.MULT.CYCLIC LR3 {{ cr.tmp }} LR0 ;;
{{ rc() }}
LD.MULT R0 LR3 {{ cr.ones }} ;;
{{ mul('LR0', cr.const_qf, 'SUB') }}
{{ store('relu', dst) }}
LD.MULT.CYCLIC {{ dst }} {{ cr.tmp }} LR0 ;;
{{ rc() }}
LD.MULT R0 LR0 {{ cr.ones }} ;;
{{ mul('LR0', cr.const_qf, 'ADD') }}
{{ store('identity', dst) }}
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
INC LR3 2 ; INC LR4 1 ;;
INC LR8 3 ;;
chunk:
LD.MULT R0 LR0 {{ cr.ones }} ;;
LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR9 ;;
LD.MULT R0 LR8 {{ cr.ones }} ;;
MULT.RC.VE LR9 {{ cr.fp_slope if format == 'fp32' else cr.nx_slope }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{{ mul('LR0', cr.const_qf, 'ADD') }}
{{ step('LR0') }}
SET LR6 CR0 ; SET LR7 CR0 ; ADD LR2 LR1 CR0 ;;
column:
LD.MULT R0 LR8 {{ cr.ones }} ;;
MULT.RC.VE LR9 {{ cr.fp_slope if format == 'fp32' else cr.nx_slope }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% for k in range(3) %}
LD.MULT.CYCLIC LR6 {{ cr.bounds }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.const_qf }}.L ; ACC.SUB ; INC LR6 1 ;;
{% endfor %}
LD.MULT R0 LR4 {{ cr.ones }} ;;
{{ mul('LR0', cr.const_qf, 'ADD') }}
{{ step('LR4') }}
LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
{{ rc() }}
LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR0 ;;
{{ rc('SUB') }}
ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR0 ;;
{{ rc() }}
{{ store('identity', 'LR0') }}
ADD LR2 LR2 {{ cr.chunks }} ; INC LR7 1 ;;
BLT.S LR7 {{ cr.vocab }} column ;;
INC LR1 1 ; SET LR5 CR0 ;;
BLT.S LR1 {{ cr.chunks }} chunk ;;
HALT ;;
