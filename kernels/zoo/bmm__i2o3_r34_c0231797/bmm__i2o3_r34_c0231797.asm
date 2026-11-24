{% macro next_key(packed) %}
    {% if packed %}INC LR10 1{% else %}ADD LR10 LR10 {{ cr.stride }}{% endif %}
{% endmacro %}
{% macro dot(prefetch, packed, tag) %}
    INC LR11 1 ; MULT.RC.VV LR5 R0 0 LR0 {{ cr.head }}.H {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.head }}.H ; {% if prefetch %}{{ next_key(packed) }} ; LD.MULT R0 LR10 {{ cr.work if packed else cr.in0 }} ; DEC LR14 1 ; BNE LR14 CR1 {{ tag }}_reduce ; {% endif %};;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_out }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

group:
    SET LR3 {{ cr.out0_d1 }} ; SET LR4 LR2 ; ADD LR6 LR2 {{ cr.key_start }}.L ;;
    SET LR5 CR0 ; SET LR7 {{ cr.key_start }}.H ;;
head:
    SET LR8 LR4 ; SET LR9 {{ cr.m }} ; BEQ LR7 CR0 direct_query ;;
    SET LR10 LR6 ; SET LR12 {{ cr.tiles }}.H ; SET LR13 CR0 ;;
pack_key:
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR7 CR1 0 LR0 {{ cr.head }}.H {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.head }}.H {{ cr.qf_in0 }}.L {{ cr.work }} LR13 ; DEC LR12 1 ; ADD LR10 LR10 {{ cr.stride }} ;;
    INC LR13 1 ; BNE LR12 CR0 pack_key ;;

{% macro queries(tag, packed) %}
{{ tag }}_query:
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR0 ; SET LR10 {{ 'CR0' if packed else 'LR6' }} ; SET LR12 {{ cr.tiles }}.L ;;
{{ tag }}_tile:
    SET LR11 CR0 ; SET LR14 {{ cr.tile_count }}.H ; BNE LR12 CR1 {{ tag }}_ready ;;
    SET LR14 {{ cr.tile_count }}.L ;;
{{ tag }}_ready:
    DEC LR11 1 ; LD.MULT R0 LR10 {{ cr.work if packed else cr.in0 }} ; BEQ LR14 CR0 {{ tag }}_last ;;
{{ tag }}_reduce:
    {{ dot(true, packed, tag) }}
{{ tag }}_last:
    {{ dot(false, packed, tag) }}
    BEQ LR12 CR1 {{ tag }}_tail ;;
    {{ store('L') }}
    {{ next_key(packed) }} ; DEC LR12 1 ; B {{ tag }}_tile ;;
{{ tag }}_tail:
    {{ store('H') }}
    ADD LR8 LR8 {{ cr.stride }} ; DEC LR9 1 ; BNE LR9 CR1 {{ tag }}_query ;;
    B head_done ;;
{% endmacro %}
    {{ queries('packed', true) }}
    {{ queries('direct', false) }}
head_done:
    DEC LR3 1 ; BEQ LR3 CR1 next_group ;;
    INC.MODP2 LR5 {{ cr.head }}.L 7 ; INC.MODP2 LR7 {{ cr.head }}.L 7 ;;
    BNE LR5 CR0 key_advance ;;
    INC LR4 1 ;;
key_advance:
    BNE LR7 CR0 head ;;
    INC LR6 1 ; B head ;;
next_group:
    ADD LR2 LR2 {{ cr.group_rows }} ; DEC LR15 1 ; BNE LR15 CR1 group ;;
    HALT ;;
