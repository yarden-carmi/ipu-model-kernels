{# Each tap broadcasts one spatial lane to the output-channel accumulator. #}
{% macro coeff() %}INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0{% endmacro %}
{% macro tap() %}MULT.RC.VE LR0 LR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% endmacro %}
{% macro bias_plane(mode) %}MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ mode }}{% endmacro %}
{% macro store(ds) %}INC LR3 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3{% endmacro %}
{% set careful = 64 < n < 128 %}
{% set span = 16 if careful else 8 %}
{% set single = [2, 5, 8, 11, 14] if careful else [1, 3, 5] %}
{% macro block(count, final) %}
{% for j in range(count) %}
    {{ coeff() }} ;;
{% if j not in single %}
    {{ tap() }} ; {{ coeff() }} ;;
{% endif %}
    {{ tap() }}{% if not final or not loop.last %} ; ADD LR7 LR7 {{ cr.chunks }} ; LD.MULT R0 LR7 {{ cr.in0 }}{% endif %}{% if not final and loop.last %} ; DEC LR9 1 ; BNE LR9 CR1 k_loop{% endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR11 {{ cr.input_width }} ; SET LR3 CR0 ;;
    DEC LR3 1 ;;
group:
    SET LR12 LR1 ; SET LR14 LR11 ; SET LR15 LR8 ;;
    SET LR2 CR0 ; SET LR6 CR0 ; SET LR4 {{ cr.tiles }} ;;
    DEC LR2 1 ; DEC LR6 1 ;;
tile:
    SET LR1 LR12 ; SET LR11 LR14 ; SET LR8 LR15 ;;
    SET LR10 {{ cr.pack }} ; BGE.S LR5 {{ cr.pack }} seed ;;
    SET LR10 LR5 ;;
seed:
    INC LR2 1 ; LD.MULT R0 LR2 {{ cr.b }} ;;
    INC LR2 1 ; LD.MULT R0 LR2 {{ cr.b }} ; {{ bias_plane('.FIRST') }} ;;
    {{ bias_plane('') }} ;;
point:
    SET LR7 LR8 ; SET LR9 {{ cr.blocks }} ;;
    LD.MULT R0 LR7 {{ cr.in0 }} ;;
{% if k > span %}
k_loop:
    {{ block(span, false) }}
{% endif %}
    {{ block((k-1)%span+1, true) }}
    DEC LR10 1 ; DEC LR11 1 ; BEQ LR11 CR1 stripe ;;
    INC.MODP2 LR1 CR1 7 ;;
    BNE LR1 CR0 advanced ;;
    INC LR8 1 ; B advanced ;;
stripe:
    SET LR1 CR0 ; SET LR11 {{ cr.input_width }} ; ADD LR8 LR8 LR13 ;;
advanced:
    BNE LR10 CR0 point ;;
    BNE LR4 CR1 full_tile ;;
    BGE.S {{ cr.pack }} LR5 finish ;;
    {{ store(cr.tail) }} ; SUB LR5 LR5 {{ cr.pack }} ; B group ;;
full_tile:
    {{ store(cr.full) }} ; DEC LR4 1 ; B tile ;;
finish:
    {{ store(cr.last_ds) }} ; HALT ;;
