{# Load one shifted key chunk into the cyclic register, then reuse it for
   all query rows in the output tile. Each dot reduces into one output lane. #}
{% macro dot(tag, first, tail, limit) %}
{% set ds = cr.ds_k ~ ('.H' if tail else '.L') %}
    {# The branch reads the old slot index; AGG and the next load read the
       incremented indices. Finish separately to avoid an out-of-tile load. #}
    DEC {{ limit }} 3 ; DEC LR14 1 ;;
    BLT.S {{ limit }} LR14 {{ tag }}_last ;;
{{ tag }}_dot:
    INC LR14 1 ; ADD LR13 LR13 {{ cr.a_view }}.L ; LD.MULT R0 LR13 {{ cr.query }} ;
    MULT.RC.VV LR4 R0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR14 {{ ds }} ;
    BLT.S LR14 {{ limit }} {{ tag }}_dot ;;
{{ tag }}_last:
    INC LR14 1 ; ADD LR13 LR13 {{ cr.a_view }}.L ; INC {{ limit }} 3 ;
    MULT.RC.VV LR4 R0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR14 {{ ds }} ;;
{% endmacro %}
{% macro chunk(tag, first, tail) %}
{{ tag }}:
    LD.MULT.CYCLIC LR12 {{ cr.bbase }} LR0 ; ADD LR14 LR12 CR1 ;;
{% if tail %}
    ADD LR13 LR15 LR4 ;;
    BLE.S LR13 LR1 {{ tag }}_loaded ;;
{% else %}
    BEQ LR4 CR0 {{ tag }}_loaded ;;
{% endif %}
    LD.MULT.CYCLIC LR14 {{ cr.bbase }} LR1 ;;
{{ tag }}_loaded:
    SET LR14 CR0 ; SET LR13 LR10 ;;
    {# Advance the query chunk offset independently of the tile's row stride. #}
    LD.MULT R0 LR13 {{ cr.query }} ; BGT.S LR11 LR1 {{ tag }}_wide ;;
    {{ dot(tag ~ '_narrow', first, tail, 'LR11') }}
    B {{ tag }}_done ;;
{{ tag }}_wide:
    {{ dot(tag ~ '_wide', first, tail, 'LR1') }}
{{ tag }}_done:
{% if tail %}
    SUB LR13 LR13 {{ cr.pitch }}.L ;;
    INC LR13 1 ;;
    B store ;;
{% else %}
    INC LR12 1 ; INC LR10 1 ; DEC LR15 128 ; B reduce ;;
{% endif %}
{% endmacro %}

{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_m }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
{% endmacro %}

{# Convert the query-major lane layout into K-contiguous dot-product rows
   once, before those rows are reused across all key columns. #}
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    INC LR4 128 ;;
stage_head:
    SET LR7 CR0 ; SET LR8 CR0 ; SET LR9 LR0 ;;
stage_row:
    SET LR10 CR0 ; SET LR11 LR9 ;;
stage_key:
    LD.MULT R0 LR11 CR0 ;;
    MULT.EE LR8 CR1 0 LR5 {{ cr.ds_k }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR10 {{ cr.ds_k }}.L ;;
    INC LR10 1 ; ADD LR11 LR11 LR1 ;;
    BLT.S LR10 {{ cr.kh }}.L stage_key ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds_k }}.H {{ cr.qf_in0 }}.L {{ cr.query }} LR6 ;;
    INC LR6 1 ; INC LR7 1 ; INC LR8 1 ;;
    BEQ LR7 LR3 stage_next_head ;;
    BLT.S LR8 LR4 stage_row ;;
    SET LR8 CR0 ; INC LR9 1 ; B stage_row ;;
stage_next_head:
    ADD LR0 LR0 LR2 ; BNE LR6 {{ cr.a_end }} stage_head ;;
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR1 128 ; SET LR3 CR0 ; SET LR5 CR0 ;;
group:
    SET LR6 {{ cr.kh }}.H ; SET LR4 CR0 ;;
group_lane:
    BLT.S LR6 LR1 head ;;
    DEC LR6 128 ; INC LR4 1 ; B group_lane ;;
head:
    SET LR7 LR3 ; SET LR8 LR5 ; SET LR9 {{ cr.mn }}.H ;;
column:
    SET LR10 LR2 ; SET LR11 {{ cr.mn }}.L ;;
tile:
    SET LR15 {{ cr.kh }}.L ; SET LR12 LR7 ;;
    BLE.S LR15 LR1 first_tail ;;
    {{ chunk('first_full', true, false) }}
reduce:
    BLE.S LR15 LR1 next_tail ;;
    {{ chunk('next_full', false, false) }}
    {{ chunk('first_tail', true, true) }}
    {{ chunk('next_tail', false, true) }}
store:
    BLE.S LR11 LR1 store_tail ;;
    {{ output('L') }}
    DEC LR11 128 ; INC LR8 1 ; SET LR10 LR13 ;;
    B tile ;;
store_tail:
    {{ output('H') }}
    DEC LR9 1 ; BEQ LR9 CR1 next_head ;;
    ADD LR7 LR7 {{ cr.pitch }}.H ; ADD LR8 LR8 {{ cr.out_pitch }}.H ;;
    SUB LR8 LR8 {{ cr.out_pitch }}.L ;;
    INC LR8 1 ; B column ;;
next_head:
    ADD LR4 LR4 {{ cr.kh }}.L ; DEC LR6 1 ;;
normalize:
    BLT.S LR4 LR1 normalized ;;
    DEC LR4 128 ; INC LR3 1 ; B normalize ;;
normalized:
    BEQ LR6 CR0 next_group ;;
    ADD LR2 LR2 {{ cr.pitch }}.L ; ADD LR5 LR5 {{ cr.out_pitch }}.L ; B head ;;
next_group:
    SUB LR2 LR13 {{ cr.a_view }}.H ;;
    BEQ LR2 {{ cr.a_end }} end ;;
    ADD LR3 LR3 {{ cr.b_next_group }} ; ADD LR5 LR8 CR1 ; B group ;;
end:
    HALT ;;
