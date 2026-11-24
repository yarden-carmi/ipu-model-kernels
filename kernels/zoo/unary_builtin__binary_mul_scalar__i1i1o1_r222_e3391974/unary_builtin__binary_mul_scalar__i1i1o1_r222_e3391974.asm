{% set chunks = (out0_d1 + 127) // 128 %}
{% set rows = out0_d0 * chunks %}
{% macro store(ds,advance='') %}
    MULT.RC.VE LR10 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 {{ advance }} ;;
{% endmacro %}
{% macro clip(a,b,dst,neg,reverse=false,prefetch='',after='') %}
{% if a == b %}
    {# The unsplit reciprocal gives the signed product in one multiply. #}
    MULT.RC.VE {{ a }} LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {% if reverse %}ACC.ADD.FIRST{% else %}ACC.SUB.FIRST{% endif %} {{ prefetch }} ;;
{% else %}
    MULT.RC.VE {{ a }} LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST {{ prefetch }} ;;
    MULT.RC.VE {{ b }} LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; LD.MULT R1 LR9 {{ cr.s0 }} ;;
    MULT.EE LR3 {{ cr.base_cap }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if a == 'LR10' %}; LD.MULT.CYCLIC LR13 {{ cr.s0 }} LR10{% endif %} ;;
{% endif %}
    MULT.EE LR3 {{ cr.neg_cap }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.MAX ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.s0 }} {{ dst }} {% if neg %}; LD.MULT R1 {{ neg }} {{ cr.s0 }}{% endif %} {{ after }} ;;
{% endmacro %}
{% macro reciprocal(scale,pos,neg='') %}
    MULT.EE LR0 {{ scale }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST {% if scale == 'CR1' %}; ADD LR11 LR9 LR7 ; SET LR15 LR10 ; SET LR13 LR8{% endif %} ;;
{% if scale == 'CR1' %}
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; SET LR5 LR11 ; SET LR14 LR8 ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_s0 }} {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ pos }} {% if scale == 'CR1' %}; INC LR13 3 ; INC LR14 4 ; INC LR15 128{% else %}; SET LR2 CR1{% endif %} ;;
{% if scale != 'CR1' %}
    LD.MULT R0 {{ pos }} {{ cr.s0 }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ; LD.MULT R1 LR9 {{ cr.s0 }} ; INC LR5 1 ;;
    ACTIVATE.QUANTIZE relu {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ neg }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE relu {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ pos }} {% if rows <= 8 %}; LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR15{% endif %} ;;
{% endif %}
{% endmacro %}
{% macro merge(boost,next_base='',prefetch='') %}
    MULT.RC.VE LR10 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.SUB.FIRST ; LD.MULT.CYCLIC {{ boost }} {{ cr.s0 }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.neg_inv }} 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.MAX ; ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.s0 }} {{ boost }} {{ next_base }} {{ prefetch }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR7 CR1 ;;
    LD.MULT R0 LR0 {{ cr.in1 }} ; INC LR3 128 ; INC LR7 1 ; SET LR9 CR1 ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; INC LR9 2 ; SET LR10 LR3 ; SET LR4 CR1 ;;
    ACTIVATE.QUANTIZE exp2 {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} LR9 ; INC LR10 128 ; ADD LR8 LR9 CR1 ; SET LR1 CR0 ;;
    {{ reciprocal('CR1','LR11') }}
    {{ reciprocal(cr.factor,'LR0','LR4') }}
    {# Materialize 2 exactly in the format used by both output halves. #}
    MULT.EE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.full }}.H {{ cr.qf_out0 }}.L {{ cr.s0 }} LR5 ;;
{% macro compute_row(advance='') %}
    MULT.RC.VE LR15 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR7 ; LD.MULT R0 LR11 {{ cr.s0 }} {{ advance }} ;;
    MULT.RC.VE LR15 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ; ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR8 ; LD.MULT R1 LR9 {{ cr.s0 }} ;;
    {{ clip('LR15','LR15','LR13','',false,'; LD.MULT.CYCLIC LR7 ' ~ cr.s0 ~ ' LR0') }}
    {{ clip('LR15','LR15','LR14','',true,'; LD.MULT R0 LR0 ' ~ cr.s0,'; LD.MULT.CYCLIC LR8 ' ~ cr.s0 ~ ' LR10') }}
    {{ clip('LR0','LR10','LR7','LR4',false,'; LD.MULT R1 LR4 ' ~ cr.s0) }}
    {{ clip('LR10','LR0','LR8','',false,'','; LD.MULT R1 LR5 ' ~ cr.s0) }}
    {{ merge('LR7','; LD.MULT.CYCLIC LR14 ' ~ cr.s0 ~ ' LR10') }}
    {{ merge('LR8','','; LD.MULT.CYCLIC LR7 ' ~ cr.s0 ~ ' LR15') }}
    MULT.RC.VE LR15 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR8 {{ cr.s0 }} LR10 ;;
{% endmacro %}
{# For short shapes, overlap each store with the next input load. LR1
   tracks the output row; LR2 stays one row ahead for the prefetch. #}
{% if rows <= 8 %}
{% for i in range(rows) %}
    {{ compute_row('; INC LR1 1 ; INC LR2 1' if i else '') }}
    {% set ds = cr.tail if out0_d1 % 128 and (i + 1) % chunks == 0 else cr.full %}
    {{ store(ds, '; LD.MULT.CYCLIC LR2 ' ~ cr.in0 ~ ' LR15' if i + 1 < rows else '') }}
{% endfor %}
{% else %}
    SET LR6 {{ cr.loop }}.L ;;
row:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR15 ;;
    {{ compute_row() }}
{% if out0_d1 % 128 == 0 %}
    {{ store(cr.full) }}
    INC LR1 1 ;;
    BLT.S LR1 LR6 row ;;
{% else %}
    SET LR6 {{ cr.loop }}.H ;;
    BEQ LR2 LR6 tail ;;
    {{ store(cr.full) }}
    INC LR1 1 ; INC LR2 1 ;;
    B row ;;
tail:
    {{ store(cr.tail) }}
    INC LR1 1 ; SET LR2 CR1 ;;
    SET LR6 {{ cr.loop }}.L ;;
    BLT.S LR1 LR6 row ;;
{% endif %}
{% endif %}
    HALT ;;
