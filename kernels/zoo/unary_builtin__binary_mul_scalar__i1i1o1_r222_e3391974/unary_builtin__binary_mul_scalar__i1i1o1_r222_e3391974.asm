{% macro store(ds,advance='') %}
    MULT.RC.VE LR10 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 {{ advance }} ;;
{% endmacro %}
{% macro clip(dst,reverse=false,boost=false,prefetch='',during='',advance='') %}
{% if boost %}
    MULT.RC.VE {{ 'LR10' if reverse else 'LR0' }} LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST {{ advance }} ;;
    MULT.RC.VE {{ 'LR0' if reverse else 'LR10' }} LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; LD.MULT R1 LR9 {{ cr.s0 }} ;;
    MULT.EE LR3 {{ cr.base_cap }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {{ during }} ;;
    MULT.EE LR3 {{ cr.neg_cap }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.MAX ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.s0 }} {{ dst }} {{ prefetch }} ;;
{% else %}
    MULT.RC.VE LR15 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ 'ACC.SUB.FIRST' if reverse else 'ACC.ADD.FIRST' }} ; ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.s0 }} {{ dst }} {{ prefetch }} ;;
{% endif %}
{% endmacro %}
{% macro reciprocal(scale,pos) %}
{% if scale == 'CR1' %}
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_s0 }} {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ pos }} ;;
{% else %}
    MULT.EE LR0 {{ scale }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_s0 }} {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ pos }} ;;
{% endif %}
{% endmacro %}
{% macro merge(boost,next_base='',prefetch='') %}
    MULT.RC.VE LR10 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC {{ boost }} {{ cr.s0 }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.neg_inv }} 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.MAX ; ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.s0 }} {{ boost }} {{ next_base }} {{ prefetch }} ;;
{% endmacro %}
    SET LR2 CR1 ; SET LR4 CR1 ; INC LR9 3 ; LD.MULT R0 LR0 {{ cr.in1 }} ;;
    INC LR3 128 ; INC LR7 2 ; INC LR8 4 ; MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} LR9 ;;
    ADD LR10 LR3 LR3 ; INC LR11 5 ; INC LR12 6 ; LD.MULT R1 LR9 {{ cr.s0 }} ;;
    INC LR13 7 ; INC LR14 8 ; ADD LR15 LR10 LR3 ; MULT.EE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.full }}.H {{ cr.qf_out0 }}.L {{ cr.s0 }} LR12 ;;
    {{ reciprocal('CR1','LR11') }}
    {{ reciprocal(cr.factor,'LR0') }}
    LD.MULT R0 LR0 {{ cr.s0 }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ; ACTIVATE.QUANTIZE relu {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} LR4 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE relu {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} LR0 ;;
{% macro compute_row(advance='') %}
    MULT.RC.VE LR15 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR7 ; LD.MULT R0 LR11 {{ cr.s0 }} {{ advance }} ;;
    MULT.RC.VE LR15 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ; ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR8 ; LD.MULT.CYCLIC LR7 {{ cr.s0 }} LR0 ;;
    {{ clip('LR13',prefetch='; LD.MULT.CYCLIC LR8 ' ~ cr.s0 ~ ' LR10') }}
    {{ clip('LR14',true,prefetch='; LD.MULT R0 LR0 ' ~ cr.s0) }}
    {{ clip('LR7',false,true,prefetch='; LD.MULT R1 LR4 ' ~ cr.s0,advance='; LD.MULT R1 LR4 ' ~ cr.s0) }}
    {{ clip('LR8',true,true,prefetch='; LD.MULT.CYCLIC LR13 ' ~ cr.s0 ~ ' LR10',during='; LD.MULT R0 LR12 ' ~ cr.s0) }}
    {{ merge('LR7','; LD.MULT.CYCLIC LR14 ' ~ cr.s0 ~ ' LR10') }}
    {{ merge('LR8','','; LD.MULT.CYCLIC LR7 ' ~ cr.s0 ~ ' LR15') }}
    MULT.RC.VE LR15 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR8 {{ cr.s0 }} LR10 ;;
{% endmacro %}
{% set chunks = (out0_d1 + 127) // 128 %}
{% set rows = out0_d0 * chunks %}
{# For short shapes, overlap each store with the next input load. LR1
   tracks the output row; LR2 stays one row ahead for the prefetch. #}
{% if rows <= 8 %}
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR15 ;;
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
