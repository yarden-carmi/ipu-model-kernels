{# Within a phase the feature is fixed and the token lane advances. #}
{% macro gcd(a,b) -%}
    {%- if b == 0 -%}{{ a }}{%- else -%}{{ gcd(b,a%b) }}{%- endif -%}
{%- endmacro %}
{% set g = gcd(in0_d2,m)|int %}
{% set period = in0_d2//g %}
{% set step = m//g %}
{% set fast = k%period == 0 and step <= 128 and 128%step == 0 %}
{% set block = 128//step %}
{% set length = k//period %}
{% set q = m//in0_d2 %}
{% macro fetch() %}LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1{% endmacro %}
{% macro mac(src, first=false) %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro reduce(label, count, repeat=false, paired=false) %}
    LD.MULT R0 LR9 {{ cr.in0 }} ; SET LR11 LR7 ; SET LR12 LR7 ;;
    {% if paired %}
    LD.MULT R1 LR9 {{ cr.in0 }} ; INC LR9 1 ; DEC LR11 {{ step }} ; INC LR12 {{ (count-2)*step }} ;;
    {% else %}
    DEC LR11 {{ step }} ; INC LR9 1 {% if repeat %}; DEC LR13 1{% endif %} ;;
    {% if count > 2 %}INC LR12 {{ (count-2)*step }} ;;{% elif count == 1 %}DEC LR12 {{ step }} ;;{% endif %}
    {% endif %}
{{ label }}:
    {{ mac('LR11') }} ; {{ fetch() }} ; INC LR11 {{ step }} ; BLT.S LR11 LR12 {{ label }} ;;
    {% if repeat %}BNE LR13 CR0 full_chunk ;;{% endif %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR5 CR0 ; SET LR10 {{ cr.m }} ; SET LR15 CR0 ;;
    DEC LR5 1 ; INC LR15 128 ;;
pixel:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
    {{ fetch() }} ;;
tile:
    {{ mac('CR1', true) }} ; {{ fetch() }} ; SET LR3 LR1 ; SET LR7 LR2 ;;
    SET LR8 {% if fast %}CR0{% else %}{{ cr.k }}{% endif %} ;;
{% if fast %}
    {% if period == 65536 %}SET LR8 {{ cr.k }} ;;{% else %}INC LR8 {{ period }} ;;{% endif %}
{% endif %}
phase:
{% if fast %}
    {% if length > block and length <= 2*block and block > 1 %}
    SET LR9 LR3 ;;
    {{ reduce('paired', length, paired=true) }}
    {% else %}
    SET LR9 LR3 ; SET LR13 CR0 ;;
    {% if length//block %}
    {% if length//block == 65536 %}SET LR13 {{ cr.k }} ;;{% else %}INC LR13 {{ length//block }} ;;{% endif %}
full_chunk:
    {{ reduce('full', block, true) }}
    {% endif %}
    {% if length%block %}{{ reduce('remainder', length%block) }}{% endif %}
    {% endif %}
{% else %}
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
    {{ mac('LR7') }} ; {{ fetch() }} ;;
{% endif %}
    DEC LR8 1 ; BEQ LR8 CR1 finish ;;
    ADD LR3 LR3 {{ cr.delta }} ; BGE.S LR3 {{ cr.wrap }} phase_wrap ;;
{% if q %}
    {% if q%128 %}INC LR7 {{ q%128 }} ;;{% endif %}
    {% if q//128 %}INC LR3 {{ q//128 }} ;;{% endif %}
    BGE.S LR7 LR15 lane_wrap ;;
{% endif %}
    B phase ;;
phase_wrap:
    SUB LR3 LR3 {{ cr.span }} ; INC LR7 {{ q%128+1 }} ;;
    {% if q//128 %}INC LR3 {{ q//128 }} ;;{% endif %}
    BLT.S LR7 LR15 phase ;;
lane_wrap:
    DEC LR7 128 ; INC LR3 1 ; B phase ;;
finish:
    DEC LR6 1 ; BEQ LR6 CR1 tail ;;
    {{ store(cr.full) }}
    B tile ;;
tail:
    {{ store(cr.tail) }}
    DEC LR10 1 ; BEQ LR10 CR1 done ;;
    ADD LR1 LR1 {{ cr.pitch }} ;;
    BLT.S LR1 {{ cr.span }} pixel ;;
    SUB LR1 LR1 {{ cr.span }} ; INC LR2 1 ;;
    BLT.S LR2 LR15 pixel ;;
    DEC LR2 128 ; INC LR1 1 ; B pixel ;;
done:
    HALT ;;
