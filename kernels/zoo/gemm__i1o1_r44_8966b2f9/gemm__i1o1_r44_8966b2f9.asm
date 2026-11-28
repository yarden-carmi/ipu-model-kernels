{% set pair = out0_d1 <= 32 and out0_d3 % 2 == 0 %}
{% macro coeff() %}INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.coeff if bias else cr.precise }} LR0{% endmacro %}
{% macro store(ds) %}INC LR5 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5{% endmacro %}
    SET LR0 CR0 ; SET LR4 CR0 ;;
    SUB LR5 LR0 CR1 ;;
{% if not bias %}
{% macro dots(label) %}
    SET LR11 {{ cr.chunks }} ;;
{{ label }}:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
{% for d in range(2) %}
    {{ coeff() }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ cr.full }}.L{% if loop.last %} ; INC LR6 1 ; DEC LR11 1 ; BNE LR11 CR1 {{ label }}{% endif %} ;;
{% endfor %}
{% endmacro %}
pixel:
    SUB LR1 LR0 CR1 ; SET LR12 LR15 ;;
{% macro clear() %}
    SET LR2 CR0 ; SET LR8 {{ cr.ra1 }} ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endmacro %}
block:
    {{ clear() }}
channel:
    SET LR6 LR4 ;;
    {{ dots('dot_first') }}
    INC LR2 1 ; DEC LR12 1 ; DEC LR8 1 ;;
    BEQ LR12 CR0 last_block ;;
    BNE LR8 CR0 channel ;;
    {{ store(cr.active) }} ; B block ;;
last_block:
{% if pair %}
    SUB LR1 LR0 CR1 ; SET LR12 LR15 ; ADD LR7 LR4 {{ cr.chunks }} ;;
second_channel:
    SET LR6 LR7 ;;
    {{ dots('dot_second') }}
    INC LR2 1 ; DEC LR12 1 ; BNE LR12 CR1 second_channel ;;
{% endif %}
    {{ store(cr.active if pair else cr.tail) }} ;;
    ADD LR4 LR4 {{ cr.input_stride }} ; DEC LR14 1 ; BNE LR14 CR1 pixel ;;
    HALT ;;
{% else %}
{% macro mac(src, mode='ADD') %}MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{# Stream one coefficient row per MAC. The mixed-precision tile stores
   the first eight taps of each 16-tap group as two digits. #}
{% macro taps(count, repeat=false, label='', more=false) %}
{% for j in range(count) %}
{% if bias and k == 384 and n == 128 and j % 16 >= 8 %}
    {{ mac('LR2') }}{% if repeat or more or not loop.last %} ; {{ coeff() }}{% endif %} ; INC LR2 1{% if repeat and loop.last %} ; DEC LR9 1 ; BNE LR9 CR1 {{ label }}{% endif %} ;;
{% else %}
    {{ mac('LR2') }} ; {{ coeff() }} ; INC LR2 1 ;;
    {{ mac('LR2') }}{% if pair or repeat or more or not loop.last %} ; {{ coeff() }}{% endif %}{% if pair %} ; INC LR3 1{% endif %}{% if not pair and repeat and loop.last %} ; DEC LR9 1 ; BNE LR9 CR1 {{ label }}{% endif %} ;;
{% endif %}
{% if pair %}
    {{ mac('LR3') }} ; {{ coeff() }} ;;
    {{ mac('LR3') }}{% if repeat or more or not loop.last %} ; {{ coeff() }}{% endif %}{% if repeat and loop.last %} ; DEC LR9 1 ; BNE LR9 CR1 {{ label }}{% endif %} ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro chunk(count, label, more) %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SUB LR2 LR0 CR1 ; SET LR9 LR0 ;;
{% if pair %}
    LD.MULT R1 LR7 {{ cr.in0 }} ; SET LR3 {{ cr.ra1 }} ;;
    DEC LR3 1 ;;
{% endif %}
{% set groups = (count-1)//16 %}
{% if groups %}
    INC LR9 {{ groups }} ;;
{{ label }}:
    {{ taps(16,true,label) }}
{% endif %}
    {{ taps((count-1)%16+1,more=more) }}
{% endmacro %}
pixel:
    SUB LR1 LR0 CR1 ; SET LR8 {{ cr.blocks }} ;;
block:
    {{ coeff() }} ; SET LR6 LR4 ; SET LR11 {{ cr.chunks }} ;;
    {{ mac('CR1','ADD.FIRST') }} ; {{ coeff() }}{% if pair %} ; ADD LR7 LR4 {{ cr.chunks }}{% endif %} ;;
    {{ mac('CR1') }} ; {{ coeff() }} ;;
{% if k > 128 %}
    DEC LR11 1 ;;
full_chunk:
    {{ chunk(128,'full_taps',true) }}
{% if pair %}
    INC LR7 1 ;;
{% endif %}
    INC LR6 1 ; DEC LR11 1 ; BNE LR11 CR1 full_chunk ;;
{% endif %}
    {{ chunk((k-1)%128+1,'tail_taps',false) }}
    DEC LR8 1 ;;
{% if not pair %}
    BEQ LR8 CR0 last_block ;;
    {{ store(cr.active) }} ; B block ;;
last_block:
{% endif %}
    {{ store(cr.active if pair else cr.tail) }} ;;
    ADD LR4 LR4 {{ cr.input_stride }} ; DEC LR14 1 ; BNE LR14 CR1 pixel ;;
    HALT ;;
{% endif %}
