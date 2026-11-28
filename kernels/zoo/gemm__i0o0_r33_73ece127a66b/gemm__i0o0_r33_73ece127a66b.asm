{# LR0 is cyclic slot zero. LR4 streams constants in channel order.
   LR5 is the output row; LR8 is the sample tile within a feature. #}
{% macro mac(prefetch, branch='') %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1{% if prefetch %} ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.width }}{% endif %}{{ branch }} ;;
{% endmacro %}
{% macro chunk(count, label) %}
    LD.MULT R0 LR4 {{ cr.w }} ; SET LR3 {{ cr.minusone }} ; INC LR4 1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.width }} ;;
{% if count == 128 %}
{% for group in range(4) %}
{% for i in range(32) %}
{% if group == 3 and i == 31 %}
    {{ mac(false, ' ; DEC LR7 1 ; BNE LR7 CR1 full_chunk') }}
{% else %}
    {{ mac(true) }}
{% endif %}
{% endfor %}
{% endfor %}
{% elif count > 1 %}
{{ label }}_lane:
    {{ mac(true, ' ; BLT.S LR3 ' ~ cr.last_tail ~ ' ' ~ label ~ '_lane') }}
    {{ mac(false) }}
{% else %}
    {{ mac(false) }}
{% endif %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 {{ cr.minusone }} ; SET LR6 {{ cr.minusone }} ;;
    SET LR10 {{ cr.n }} ;;
channel:
    SET LR8 CR0 ; SET LR9 {{ cr.width }} ;;
tile:
    SUB LR2 LR8 {{ cr.width }} ; SET LR4 LR6 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR7 {{ cr.chunks }} ;;
{% if k >= 128 %}
full_chunk:
    {{ chunk(128, 'full') }}
{% endif %}
{% if k % 128 %}
    {{ chunk(k % 128, 'partial') }}
{% endif %}
    DEC LR9 1 ; BEQ LR9 CR1 last_tile ;;
    {{ store(cr.full) }}
    INC LR8 1 ; B tile ;;
last_tile:
    {{ store(cr.tail) }}
    SET LR6 LR4 ; DEC LR10 1 ; BNE LR10 CR1 channel ;;
    HALT ;;
