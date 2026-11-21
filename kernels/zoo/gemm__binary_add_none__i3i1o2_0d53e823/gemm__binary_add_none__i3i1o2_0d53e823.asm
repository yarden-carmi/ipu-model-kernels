{# R0 holds a reduction chunk. The cyclic register ping-pongs weight planes. #}
{% macro prime() %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
{% endmacro %}
{% macro dot(s, first=false, pipeline=false) %}
{% for p in range(6) %}
    MULT.RC.VE {{ 'LR1' if p % 2 else 'LR0' }} {{ s }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first and p == 0 %}.FIRST{% endif %}{% if p < 5 or pipeline %} ; LD.MULT.CYCLIC LR4 {{ cr.w }} {{ 'LR0' if p % 2 else 'LR1' }} ; INC LR4 1{% endif %}{% if s == 'LR3' and p == 0 %} ; INC LR3 1{% endif %}{% if pipeline and p == 5 %} ; BNE LR3 LR11 lane{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.slot }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR10 {{ cr.rows }} ;;
    SET LR9 CR0 ; SET LR14 CR0 ; SET LR15 LR13 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR7 {{ cr.s0_k }} ;;
{{ prime() }}
{{ dot('CR1', true) }}
load_input:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR3 CR0 ; SET LR11 LR7 ;;
    BLT.S LR7 {{ cr.slot }} chunk_size ;;
    SET LR11 {{ cr.slot }} ;;
chunk_size:
    SUB LR7 LR7 LR11 ; DEC LR11 2 ; DEC LR3 1 ;;
{{ prime() }}
    BLT.S LR11 CR0 final_lane ;;
lane:
{{ dot('LR3', false, true) }}
final_lane:
{{ dot('LR3') }}
    INC LR2 1 ; BNE LR7 CR0 load_input ;;
store_tile:
    LD.MULT R0 LR9 {{ cr.in1 }} ; DEC LR6 1 ;;
    BEQ LR6 CR0 last_tile ;;
{{ store(cr.full) }}
    INC LR5 1 ; INC LR9 1 ; B tile ;;
last_tile:
{{ store(cr.tail) }}
    INC LR5 1 ; SET LR8 LR2 ; DEC LR10 1 ;;
    BEQ LR10 CR0 done ;;
    ADD LR9 LR9 LR12 ; DEC LR15 1 ;;
    BNE LR15 CR0 row ;;
    ADD LR14 LR14 {{ cr.tiles }} ; SET LR15 LR13 ;;
    SET LR9 LR14 ; B row ;;
done:
    HALT ;;
