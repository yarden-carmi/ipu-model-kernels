{% macro weight(slot) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1
{%- endmacro %}
{% macro mac(slot, next_slot, refill=true) %}
    MULT.RC.VE {{ slot }} LR3 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {% if refill %}{{ weight(next_slot) }} ; {% endif %}INC LR3 1 ;;
{% endmacro %}
{% macro quad(refill=true) %}
{% for i in range(4) %}
    {{ mac('LR0' if i % 2 == 0 else 'LR2', 'LR2' if i % 2 == 0 else 'LR0', refill or not loop.last) }}
{% endfor %}
{% endmacro %}
{% macro bias_digit(first) %}
    LD.MULT.CYCLIC LR13 {{ cr.b }} LR0 ; INC LR13 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR5 {{ cr.m }} ; SET LR7 CR0 ;;
    SET LR11 CR0 ; SET LR2 {{ cr.width }} ;;
row:
    SET LR4 CR0 ; SET LR6 CR0 ;;
    DEC LR4 1 ;;
{% if bias %}
    SET LR13 CR0 ;;
    DEC LR13 1 ;;
{% endif %}
tile:
    SET LR8 LR11 ; SET LR9 {{ cr.chunks }} ;;
    SUB LR8 LR8 CR1 ;;
{% if bias %}
{% for i in range(8) %}
    {{ bias_digit(loop.first) }}
{% endfor %}
{% else %}
    MULT.EE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
chunk:
    LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR8 1 ; SET LR12 {{ cr.planes }} ;;
plane:
    SET LR3 CR0 ; SET LR10 {{ cr.groups }} ;;
    DEC LR3 1 ;;
    {{ weight('LR0') }} ;;
group:
    {{ quad() }}
    DEC LR10 1 ;;
    BNE LR10 CR0 group ;;
    {{ quad(false) }}
    DEC LR12 1 ;;
    BNE LR12 CR0 plane ;;
    DEC LR9 1 ;;
    BNE LR9 CR0 chunk ;;
    INC LR6 1 ;;
    BEQ LR6 {{ cr.tiles }} tail ;;
    {{ store('CR15') }}
    INC LR7 1 ; B tile ;;
tail:
    {{ store(cr.tail) }}
    INC LR7 1 ; ADD LR11 LR11 {{ cr.chunks }} ; DEC LR5 1 ;;
    BNE LR5 CR0 row ;;
    HALT ;;
