{# LR2 is the physical input row, LR3 its feature-row component, and
   LR10 the lane. Advance the logical NCHW index without dividing at runtime. #}
{% macro add_step(rem) %}ADD LR2 LR2 {{ rem }} ; ADD LR3 LR3 {{ rem }}{% endmacro %}
{% macro advance(rem, quot, blocks, name, preadded=false) %}
{% if not preadded %}
    {{ add_step(rem) }} {% if quot %}; ADD LR10 LR10 {{ cr.quot }}{% endif %} ;;
{% endif %}
    BLT.S LR3 {{ cr.span }} {{ name }}_{{ 'lane' if quot else 'done' }} ;;
    SUB LR2 LR2 {{ cr.span }} ; SUB LR3 LR3 {{ cr.span }} ; INC LR10 1 ;;
{{ name }}_lane:
    BLT.S LR10 LR1 {{ name }}_done ;;
    SUB LR10 LR10 LR1 ; INC LR2 1 ;;
{{ name }}_done:
{% if blocks %}
    ADD LR2 LR2 LR14 ;;
{% endif %}
{% endmacro %}

{% macro weight(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro mac(slot, scalar, mode='ADD') %}MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{% macro store(ds) %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; DEC LR5 1 ; SET LR13 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR11 CR0 ;;
batch:
    SET LR7 {{ cr.spatial }} ;;
spatial:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR3 LR9 ; SET LR10 LR11 ;;
    {{ weight('LR0') }} ;;
    {{ mac('LR0', 'CR1' if bias else 'CR0', 'ADD.FIRST') }} ; {{ weight('LR1') }} ; SET LR12 {{ cr.k }} ;;
    {{ mac('LR1', 'CR1' if bias else 'CR0') }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
channel:
    {{ weight('LR0') }} ;;
{% if (m // in0_d2) % 128 == 0 %}
    {{ mac('LR0', 'LR10') }} ; {{ weight('LR1') }} ; DEC LR12 1 ; BEQ LR12 CR1 last_channel ;;
    {{ mac('LR1', 'LR10') }} ; {{ add_step(cr.step) }} ;;
    {{ advance(cr.step, false, m // (128 * in0_d2), 'channel', true) }}
    LD.MULT R0 LR2 {{ cr.in0 }} ; B channel ;;
last_channel:
    {{ mac('LR1', 'LR10') }} ;;
{% else %}
    {{ mac('LR0', 'LR10') }} ; {{ weight('LR1') }} ; DEC LR12 1 ;;
    {{ mac('LR1', 'LR10') }} ; BEQ LR12 CR0 tile_done ;;
    {{ advance(cr.step, (m // in0_d2) % 128, m // (128 * in0_d2), 'channel') }}
    LD.MULT R0 LR2 {{ cr.in0 }} ; B channel ;;
{% endif %}
tile_done:
    DEC LR6 1 ; BEQ LR6 CR1 last_tile ;;
    {{ store(cr.full) }} ; B tile ;;
last_tile:
    {{ store(cr.tail) }} ; DEC LR7 1 ; BEQ LR7 CR1 batch_end ;;
    SET LR2 LR8 ; SET LR3 LR9 ; SET LR10 LR11 ; B next_spatial ;;
batch_end:
    DEC LR15 1 ; BEQ LR15 CR1 done ;;
{% if k * m == in0_d1 * in0_d2 %}
    ADD LR13 LR13 {{ cr.span }} ;;
    SET LR8 LR13 ; SET LR9 CR0 ; SET LR11 CR0 ; B batch ;;
{% endif %}
next_spatial:
    {{ advance(cr.pitch, false, false, 'spatial') }}
    SET LR8 LR2 ; SET LR9 LR3 ; SET LR11 LR10 ; BNE LR7 CR0 spatial ;;
    B batch ;;
done:
    HALT ;;
