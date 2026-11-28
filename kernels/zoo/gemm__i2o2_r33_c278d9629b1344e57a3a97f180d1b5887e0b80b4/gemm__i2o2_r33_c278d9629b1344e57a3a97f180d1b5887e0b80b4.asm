{% set rem = k % 128 %}
{% set dots = k // 128 %}
{% set last = (n - 1) % 128 + 1 %}
{% set blocks = (n + 127) // 128 %}
{% set q = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set snake = dots == 3 and rem > 2 and blocks == 2 and last >= rem and m in [2, 4, 8, 16, 32, 64, 128] %}
{% set prefetch = dots == 1 and 0 < rem <= last and blocks >= 2 and m >= 2 %}
{% macro store(ds) %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6{% endmacro %}
{% macro dot_word(slot, count, partial, more, end) %}
    MULT.RC.VV LR{{ slot }} R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR8 {{ (cr.partial if partial and slot == count - 1 else cr.full) }}.L {% if slot == 0 %}; INC LR8 1 {% endif %}{% if more or slot < count - 1 %}; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.w }}{% endif %}{% if slot == count - 1 %}{{ end }}{% endif %} ;;
{% endmacro %}
{% macro dot_loop(label, width, count, partial, end, limit='LR13') %}
{% if width > 1 %}
{{ label }}:
{% for j in range(count) %}
{{ dot_word(j, count, partial, true, ' ; BLT.S LR8 ' ~ limit ~ ' ' ~ label) }}
{% endfor %}
{% endif %}
{% for j in range(count) %}
{{ dot_word(j, count, partial, false, end) }}
{% endfor %}
{% endmacro %}
{% macro scalar_word(end) %}MULT.RC.VE LR3 LR7 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR7 1 {{ end }}{% endmacro %}
{% macro scalar_loop(label, count, end) %}
{% if count > 1 %}
{{ label }}:
    {{ scalar_word('; INC LR5 1 ; LD.MULT.CYCLIC LR5 ' ~ cr.w ~ ' LR3 ; BLT.S LR7 LR12 ' ~ label) }} ;;
{% endif %}
    {{ scalar_word(end) }} ;;
{% endmacro %}
{% macro load_rc(slot, increment=true) %}
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR{{ slot }} {% if increment %}; INC LR4 1{% endif %}
{% endmacro %}
    INC LR1 128 ; INC LR2 128 ; INC LR3 128 ;;
    ADD LR2 LR2 LR1 ; ADD LR3 LR3 LR1 ;;
    ADD LR3 LR3 LR1 ;;
    SET LR10 {{ cr.m }} ; DEC LR11 1 ; DEC LR6 {{ 2 if snake else 1 }} ;;
{% if snake %}
{# Reverse tile order on alternating tokens to keep one bias in R1 across
   the token boundary. Put the scalar passes together so they share R0. #}
{% set bits = 3 if m == 2 else 4 if m == 4 else 5 if m == 8 else 6 if m == 16 else 7 if m == 32 else 8 if m == 64 else 9 %}
{% macro snake_token(odd) %}
{% set a = cr.tile if odd else 'CR0' %}
{% set b = 'CR0' if odd else cr.tile %}
{% set ds_a = cr.tail if odd else cr.full %}
{% set ds_b = cr.full if odd else cr.tail %}
    {{ load_rc(1) }} ; SET LR9 {{ a }} ; SET LR14 {{ b }} ;;
    {{ load_rc(2) }} ; SET LR8 LR11 ; INC LR6 2 ;;
    MULT.VE LR1 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ADD LR5 LR9 LR15 ; LD.MULT R0 LR5 {{ cr.w }} ; SET LR13 {{ cr.width_limit if odd else cr.aux }} ;;
    {{ dot_loop('first_dots_' ~ odd, last if odd else 128, dots, false, ' ; INC LR4 1 ; LD.MULT R0 LR4 ' ~ cr.in0) }}
    ADD LR5 LR9 CR1 ; SET LR7 LR11 ; SET LR13 {{ cr.aux if odd else cr.width_limit }} ; LD.MULT.CYCLIC LR5 {{ cr.w }} LR3 ;;
    {{ scalar_loop('first_scalar_' ~ odd, rem, ' ; LD.MULT R1 LR14 ' ~ cr.w ~ ' ; ' ~ store(ds_a)) }}
    MULT.VE LR1 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ADD LR5 LR14 CR1 ; SET LR7 LR11 ; {{ 'DEC' if odd else 'INC' }} LR6 1 ; LD.MULT.CYCLIC LR5 {{ cr.w }} LR3 ;;
    {{ scalar_loop('second_scalar_' ~ odd, rem, ' ; INC LR5 1 ; LD.MULT R0 LR5 ' ~ cr.w ~ ' ; SET LR8 LR11') }}
    {{ dot_loop('second_dots_' ~ odd, 128 if odd else last, dots, false, ' ; INC.MODP2 LR4 CR1 ' ~ bits ~ ' ; LD.MULT.CYCLIC LR4 ' ~ cr.in0 ~ ' LR0 ; ' ~ store(ds_b) ~ (' ; DEC LR10 2 ; BNE LR10 CR1 token_pair' if odd else '')) }}
{% endmacro %}
    INC LR12 {{ rem - 3 }} ; INC LR15 {{ rem + 1 }} ; DEC LR10 1 ;;
    LD.MULT R1 LR0 {{ cr.w }} ;;
    {{ load_rc(0, false) }} ;;
token_pair:
    {{ snake_token(false) }}
    {{ snake_token(true) }}
{% else %}
{% macro bias() %}
    INC LR5 1 ; LD.MULT R0 LR5 {{ cr.w }} ;;
{% endmacro %}
{% macro seed() %}MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST{% endmacro %}
{% macro hybrid_tile(label, width, ds, extra, advance, cached_bias=false, full_tile=false, count_token=false) %}
{% set count = dots + extra %}
{% set scalar = rem if not extra else 0 %}
{% if extra %}    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR{{ dots }} ;;{% endif %}
{% set finish = ' ; INC LR6 1 ; ' ~ store(ds) ~ advance %}
{% set step = ' ; DEC LR9 1' if full_tile else ' ; DEC LR10 1' if count_token else '' %}
{% set start = 'MULT.RC.VE LR2 CR1 0 LR0 ' ~ full ~ ' ' ~ q ~ ' ; ACC.ADD.FIRST' if cached_bias else seed() %}
{% if scalar %}
    {{ start }} ; ADD LR7 LR1 LR11 ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.w }} LR3 {{ step }} ;;
    {{ scalar_loop(label ~ '_scalar', scalar, ' ; INC LR5 1 ; LD.MULT R0 LR5 ' ~ cr.w ~ ' ; SET LR8 LR11' if count else finish) }}
{% else %}
    {{ start }} ; SET LR8 LR11 ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.w }} {{ step }} ;;
{% endif %}
{% if count %}
    {{ dot_loop(label ~ '_dots', width, count, extra, finish, cr.aux if full_tile else cr.width_limit) }}
{% endif %}
{% endmacro %}
{% if prefetch %}
{# Keep tile zero's bias in the unused cyclic slot. The last dot can then
   refill the activation slot instead of loading that bias for each token. #}
{% set next_bias = ' ; INC LR5 1 ; LD.MULT R0 LR5 ' ~ cr.w %}
{% macro prefetched_token(label, advance) %}
    {{ hybrid_tile(label ~ '_first', 128, cr.full, 0, next_bias, true, true) }}
{% if blocks > 2 %}
{{ label }}_full:
    {{ hybrid_tile(label ~ '_body', 128, cr.full, 0, next_bias ~ ' ; BNE LR9 CR1 ' ~ label ~ '_full', false, true) }}
{% endif %}
    {{ hybrid_tile(label ~ '_last', last, cr.tail, 0, advance, count_token=advance != '') }}
{% endmacro %}
{% if rem > 1 %}    INC LR12 {{ 125 + rem }} ;;{% endif %}
    LD.MULT.CYCLIC LR0 {{ cr.w }} LR2 ;;
    {{ load_rc(0, false) }} ;;
prefetched_token:
    INC LR4 1 ; LD.MULT R1 LR4 {{ cr.in0 }} ; SET LR5 LR0 ; SET LR9 {{ cr.blocks }} ; BEQ LR10 CR1 final_token ;;
    {{ prefetched_token('stream', ' ; INC LR4 1 ; LD.MULT.CYCLIC LR4 ' ~ cr.in0 ~ ' LR0 ; B prefetched_token') }}
final_token:
    {{ prefetched_token('final', '') }}
{% elif k <= 512 %}
    DEC LR4 1 ;;
{% if rem > 1 %}    INC LR12 {{ 125 + rem }} ;;{% endif %}
{# Prime the bias stream. Each tile's store word loads the next bias;
   the final tile wraps to weight row zero while retiring the token. #}
    LD.MULT R0 LR0 {{ cr.w }} ;;
token:
{% for j in range(dots) %}
    {{ load_rc(j) }} {% if j == 0 %}; SET LR5 LR0 ; SET LR9 {{ cr.blocks }}{% endif %} ;;
{% endfor %}
{% if rem %}    INC LR4 1 ; LD.MULT R1 LR4 {{ cr.in0 }} {% if not dots %}; SET LR5 LR0 ; SET LR9 {{ cr.blocks }}{% endif %} ;;{% endif %}
{% if blocks > 1 %}
full_tile:
    {{ hybrid_tile('full', 128, cr.full, 0, ' ; INC LR5 1 ; LD.MULT R0 LR5 ' ~ cr.w ~ ' ; BNE LR9 CR1 full_tile', false, true) }}
{% endif %}
    {{ hybrid_tile('last', last, cr.tail, 1 if rem > last else 0, ' ; LD.MULT R0 LR0 ' ~ cr.w ~ ' ; DEC LR10 1 ; BNE LR10 CR1 token') }}
{% else %}
{# Long K uses the same channel tiles, streaming scalar activation chunks. #}
{% macro long_tile(label, ds) %}
    {{ bias() }}
    {{ seed() }} ; SET LR4 LR14 ; SET LR8 {{ cr.chunks }} ;;
{{ label }}_chunk:
    LD.MULT R1 LR4 {{ cr.in0 }} ; SET LR7 LR1 ;;
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.w }} LR3 ; DEC LR7 1 ; BEQ LR8 CR1 {{ label }}_last ;;
    {{ scalar_loop(label ~ '_scalar', 128, ' ; INC LR4 1 ; DEC LR8 1 ; B ' ~ label ~ '_chunk') }}
{{ label }}_last:
    SET LR12 {{ cr.aux }} ;;
    {{ scalar_loop(label ~ '_partial', (k - 1) % 128 + 1, ' ; INC LR6 1 ; ' ~ store(ds)) }}
    SET LR12 LR15 ;;
{% endmacro %}
    INC LR15 253 ; INC LR12 253 ;;
long_token:
    SET LR5 LR11 ; SET LR9 {{ cr.blocks }} ;;
{% if blocks > 1 %}
    DEC LR9 1 ;;
long_full:
    {{ long_tile('wide', cr.full) }}
    DEC LR9 1 ; BNE LR9 CR1 long_full ;;
{% endif %}
    {{ long_tile('narrow', cr.tail) }}
    ADD LR14 LR14 {{ cr.chunks }} ; DEC LR10 1 ; BNE LR10 CR1 long_token ;;
{% endif %}
{% endif %}
    HALT ;;
