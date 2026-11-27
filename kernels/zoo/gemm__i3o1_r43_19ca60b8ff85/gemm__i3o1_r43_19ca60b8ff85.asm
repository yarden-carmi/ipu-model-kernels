{% macro set13(v) %}
    SET LR13 CR0 ;;
{% for i in range(0, v, 255) %}    INC LR13 {{ [255,v-i]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro mac(prefetch, branch='') %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1{% if prefetch %} ; LD.MULT.CYCLIC LR2 {{ cr.tmp }} LR0 ; INC LR2 1{% endif %}{{ branch }} ;;
{% endmacro %}
{% macro chunk(count, label) %}
    LD.MULT R0 LR4 {{ cr.w }} ; SET LR3 {{ cr.minusone }} ; INC LR4 1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.tmp }} LR0 ; INC LR2 1 ;;
{% if count == 128 %}
{{ label }}_group:
{% for i in range(31) %}
    {{ mac(true, ' ; BLT.S LR3 ' ~ cr.last_full ~ ' ' ~ label ~ '_advance' if i == 30 else '') }}
{% endfor %}
    {{ mac(false, ' ; DEC LR7 1 ; BNE LR7 CR1 ' ~ label ~ '_chunk') }}
    B {{ label }}_end ;;
{{ label }}_advance:
    {{ mac(true, ' ; B ' ~ label ~ '_group') }}
{{ label }}_end:
{% elif count > 1 %}
{{ label }}_lane:
    {{ mac(true, ' ; BLT.S LR3 ' ~ cr.last_tail ~ ' ' ~ label ~ '_lane') }}
    {{ mac(false) }}
{% else %}
    {{ mac(false) }}
{% endif %}
{% endmacro %}

    SET LR5 CR0 ; SET LR6 CR0 ; SET LR8 CR0 ;;
    DEC LR5 1 ;;
batch:
    SET LR9 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
feature:
    SET LR7 CR0 ;;
gather_start:
    ADD LR4 LR6 LR10 ; SET LR14 CR0 ; SET LR15 CR0 ;;
    SET LR12 CR0 ; SET LR0 CR0 ; SET LR1 CR0 ;;
gather:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.EE LR9 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD14 7 ; ADD LR4 LR4 {{ cr.rowstep }} ; INC LR12 1 ;;
    ADDBI LRD14 1 ;;
    {{ set13(out0_d1) }}
    BLT.S LR12 LR13 gather ;;
    BNE LR7 CR0 residual ;;
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR11 ;;
    INC LR7 1 ; B gather_start ;;
residual:
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
    {{ set13(k) }}
    ADD LR2 LR11 LR13 ;;
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR2 ;;
    INC LR11 1 ; INC LR9 1 ;;
    {{ set13(in0_d3) }}
    BLT.S LR9 LR13 no_wrap ;;
    SET LR9 CR0 ; INC LR10 1 ;;
no_wrap:
    {{ set13(k) }}
    BLT.S LR11 LR13 feature ;;

    SET LR0 CR0 ; SET LR4 {{ cr.minusone }} ; SET LR10 {{ cr.n }} ;;
channel:
    SET LR2 {{ cr.minusone }} ; SET LR9 LR4 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR7 {{ cr.chunks }} ;;
{% if k >= 128 %}
full_chunk:
    {{ chunk(128, 'full') }}
{% endif %}
{% if k % 128 %}
    {{ chunk(k % 128, 'partial') }}
{% endif %}
    SET LR4 LR9 ;;
    INC LR4 1 ;;
    {{ set13(k) }}
    SET LR2 LR13 ; SET LR7 {{ cr.chunks }} ;;
    DEC LR2 1 ;;
{% if k >= 128 %}
resfull_chunk:
    {{ chunk(128, 'resfull') }}
{% endif %}
{% if k % 128 %}
    {{ chunk(k % 128, 'respartial') }}
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
    DEC LR10 1 ;;
    BNE LR10 CR0 channel ;;
{% for i in range(0, in0_d1 * in0_d2, 255) %}    INC LR6 {{ [255,in0_d1 * in0_d2-i]|min }} ;;
{% endfor %}
    INC LR8 1 ;;
    {{ set13(out0_d0) }}
    BLT.S LR8 LR13 batch ;;
    HALT ;;
