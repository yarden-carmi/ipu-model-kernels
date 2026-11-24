{# A vector holds 128 tokens for a single input feature. R0/R1 hold
   primary and correction coefficients for the current output feature. #}
{% macro xload() -%}
LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.stride_in }}
{%- endmacro %}
{% macro product(scalar, first=false) -%}
MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro features(count, branch='') %}
    {{ xload() }}{% if branch %} ; DEC LR9 1{% endif %} ;;
{% for i in range(count) %}
{% set single = i % 4 == 0 %}
    {{ product('LR7') }} ; INC LR7 1{% if single and not loop.last %} ; {{ xload() }}{% endif %}{% if single and loop.last and branch %} ; BNE LR9 CR0 {{ branch }}{% endif %} ;;
{% if not single %}
    {{ product('LR8') }} ; INC LR8 1{% if not loop.last %} ; {{ xload() }}{% elif branch %} ; BNE LR9 CR0 {{ branch }}{% endif %} ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro weights() %}
    LD.MULT R0 LR3 {{ cr.w }} ; INC LR3 1 ; SET LR7 CR0 ; SET LR8 {{ cr.width }} ;;
    LD.MULT R1 LR3 {{ cr.w }} ; INC LR3 1 ; DEC LR7 1 ; DEC LR8 1 ;;
{% endmacro %}
{% macro store(ds) -%}
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; ADD LR4 LR4 {{ cr.stride_out }}
{%- endmacro %}
    SET LR15 {{ cr.batches }} ;;
batch:
    SET LR1 LR13 ; SET LR10 {{ cr.stride_out }} ;;
tile:
    SUB LR4 LR1 {{ cr.stride_out }} ; SET LR3 CR0 ; SET LR5 {{ cr.features_out }} ;;
    DEC LR3 1 ;;
feature:
    ADD LR2 LR1 LR14 ;;
    SUB LR2 LR2 {{ cr.stride_in }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.w }} LR0 ; INC LR3 1 ;;
    {{ product('CR1', true) }} ; LD.MULT.CYCLIC LR3 {{ cr.w }} LR0 ; INC LR3 1 ;;
    {{ product('CR1') }}{% if k >= 128 %} ; SET LR6 {{ cr.chunks }}{% endif %} ;;
{% if k >= 128 %}
chunk:
    {{ weights() }}
    SET LR9 {{ cr.four }} ; DEC LR6 1 ;;
group:
    {{ features(32, 'group') }}
    BNE LR6 CR0 chunk ;;
{% endif %}
{% if k % 128 %}
    {{ weights() }}
{% if (k % 128) >= 32 %}
    SET LR9 CR0 ;;
    INC LR9 {{ (k % 128) // 32 }} ;;
tail_group:
    {{ features(32, 'tail_group') }}
{% endif %}
{% if k % 32 %}
    {{ features(k % 32) }}
{% endif %}
{% endif %}
    DEC LR5 1 ; BEQ LR10 CR1 last_tile ;;
    {{ store(cr.full) }} ; BNE LR5 CR0 feature ;;
    B next_tile ;;
last_tile:
    {{ store(cr.tail) }} ; BNE LR5 CR0 feature ;;
    SET LR13 LR4 ; ADD LR2 LR2 {{ cr.stride_in }} ; DEC LR15 1 ;;
    INC LR13 1 ; SUB LR2 LR2 {{ cr.stride_out }} ;;
    INC LR2 1 ; SUB LR14 LR2 LR13 ; BNE LR15 CR0 batch ;;
    HALT ;;
next_tile:
    INC LR1 1 ; DEC LR10 1 ; B tile ;;
