{# Replay each flattened GEMM row for every output tile. A physical
   input row holds one width strip, so the cursor wraps at in0_d3. #}
{% macro load_weight(slot) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1
{%- endmacro %}
{% macro dot(scalar, first=false) %}
{% for digit in range(3) %}
    MULT.RC.VE {{ 'LR1' if digit == 1 else 'LR0' }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first and digit == 0 %}.FIRST{% endif %}{% if digit == 0 %} ; {{ load_weight('LR1') }}{% elif digit == 1 %} ; {{ load_weight('LR0') }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR15 {{ cr.out0_d0 }} ; DEC LR5 1 ;;
row:
    SET LR4 CR0 ; SET LR14 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR3 LR9 ;;
    SET LR6 {{ cr.k }} ; {{ load_weight('LR0') }} ;;
    {{ dot('CR1', true) }}
load_input:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
tap:
    {{ load_weight('LR0') }} ;;
    {{ dot('LR3') }}
    INC LR3 1 ; DEC LR6 1 ;;
    BEQ LR3 {{ cr.in0_d3 }} strip_end ;;
    BNE LR6 CR0 tap ;;
    B finish_tile ;;
strip_end:
    SET LR3 CR0 ; INC LR2 1 ; BNE LR6 CR0 load_input ;;
finish_tile:
    DEC LR14 1 ; BEQ LR14 CR1 last ;;
    {{ store(cr.full) }}
    B tile ;;
last:
    {{ store(cr.tail) }}
    SET LR8 LR2 ; SET LR9 LR3 ;;
    DEC LR15 1 ; BNE LR15 CR1 row ;;
    HALT ;;
