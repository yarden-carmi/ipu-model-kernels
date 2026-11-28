{% macro output() %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13
{%- endmacro %}
{% macro multiply(lane, scalar='LR11') %}
    MULT.RC.VE {{ lane }} {{ scalar }} 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD
{%- endmacro %}
    INC LR15 128 ; DEC LR13 1 ;;
group:
    SET LR3 {{ cr.n_lane }}.H ; SET LR14 {{ cr.k_count }}.L ; BGT.S {{ cr.k_count }}.L LR15 large_entry ;;
    ADD LR12 LR15 LR15 ; INC.MODP2 LR3 CR0 3 ;;
    BNE LR14 LR12 stream_group ;;
    BNE LR3 CR0 stream_group ;;
    {# The panel is contiguous across heads; only the dot loop needs even n. #}
    INC.MODP2 LR3 {{ cr.n_lane }}.L 1 ;;
    BNE LR3 CR0 stream_group ;;
    SET LR12 {{ cr.k_count }}.H ;;
    INC.MODP2 LR3 LR12 3 ;;
    BEQ LR3 CR0 transpose_group ;;
stream_group:
    SET LR2 LR1 ; SET LR3 {{ cr.n_lane }}.H ; SET LR4 {{ cr.mh }}.H ;;
head:
    SET LR5 {{ cr.mh }}.L ; ADD LR7 LR3 {{ cr.n_lane }}.L ;;
    BGT.S LR7 LR15 general_row ;;
    BGT.S {{ cr.k_count }}.L LR15 general_row ;;
    SET LR12 CR1 ;;
    INC LR12 2 ;;
    BLE.S {{ cr.k_count }}.L LR12 general_row ;;

{# Retain key zero in a second cyclic slot and prefetch the next query. #}
    SET LR12 {{ cr.k_count }}.L ; SET LR8 {{ cr.k_count }}.L ;
    LD.MULT.CYCLIC LR2 {{ cr.vbase }} LR15 ;;
    DEC LR12 4 ; DEC LR8 1 ; ADD LR7 LR3 LR15 ;
    LD.MULT R0 LR0 {{ cr.in0 }} ;;
    ADD LR10 LR2 {{ cr.stride }}.L ;;
fast_row:
    MULT.VE LR15 CR0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR9 LR10 ; SET LR11 CR0 ; ADD LR0 LR0 {{ cr.stride }}.H ;
    {{ multiply('LR7', 'LR6') }} ; LD.MULT.CYCLIC LR9 {{ cr.vbase }} LR6 ;;
fast_inner:
    INC LR11 1 ; ADD LR9 LR9 {{ cr.stride }}.L ;
    {{ multiply('LR3') }} ; LD.MULT.CYCLIC LR9 {{ cr.vbase }} LR6 ; BLT.S LR11 LR12 fast_inner ;;
    INC LR11 1 ; ADD LR9 LR9 {{ cr.stride }}.L ;
    {{ multiply('LR3') }} ; LD.MULT.CYCLIC LR9 {{ cr.vbase }} LR6 ; BEQ LR5 CR1 fast_last ;;
{% macro fast_store(prefetch) %}
    {{ multiply('LR3', 'LR8') }} ; {{ output() }} ; INC LR13 1 ;
    {% if prefetch %} DEC LR5 1 ; LD.MULT R0 LR0 {{ cr.in0 }} ; B fast_row ; {% endif %} ;;
{% endmacro %}
    {{ fast_store(true) }}
fast_last:
    {{ fast_store(false) }}
    B advance_head ;;

{# Stream arbitrary K chunks when the transpose path is not applicable. #}
general_row:
    SET LR8 LR0 ; SET LR9 LR2 ; SET LR10 {{ cr.k_count }}.L ;
    MULT.VE LR6 CR0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
general_chunk:
    SET LR12 LR10 ; SET LR11 CR0 ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
    INC LR8 1 ; BLE.S LR12 LR15 general_ready ;;
    SET LR12 LR15 ;;
general_ready:
    SUB LR10 LR10 LR12 ;;
general_key:
    LD.MULT.CYCLIC LR9 {{ cr.vbase }} LR6 ; ADD LR7 LR3 {{ cr.n_lane }}.L ;;
    BLE.S LR7 LR15 general_mac ;;
    ADD LR7 LR9 CR1 ; LD.MULT.CYCLIC LR7 {{ cr.vbase }} LR15 ;;
general_mac:
    {{ multiply('LR3') }} ; INC LR11 1 ; ADD LR9 LR9 {{ cr.stride }}.L ; DEC LR12 1 ; BGT.S LR12 CR1 general_key ;;
    BNE LR10 CR0 general_chunk ;;
    {{ output() }} ; INC LR13 1 ; ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR5 1 ; BGT.S LR5 CR1 general_row ;;
advance_head:
    DEC LR4 1 ; ADD LR3 LR3 {{ cr.n_lane }}.L ;;
    BEQ LR4 CR0 next_group ;;
    BLT.S LR3 LR15 head ;;
    DEC LR3 128 ; INC LR2 1 ; B head ;;
next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.total_rows }} group ;;
    HALT ;;

{# Scatter sixteen keys and eight columns into four parity classes per half-row.
   Pair two tiles at lane 64; STRIDE then extracts 32 keys of one column. #}
{% macro init_bytes(reg, other, bytes, more) %}
    SET {{ reg }} CR0 ; SET {{ other }} CR0 ;;
{% for byte in bytes|reverse %}
{% if not loop.first %}
{% for bit in range(8) %}
    ADD {{ reg }} {{ reg }} {{ reg }} ; ADD {{ other }} {{ other }} {{ other }} ;;
{% endfor %}
{% endif %}
    {% if byte %} INC {{ reg }} {{ byte }} ; {% endif %}
    {% if more[4-loop.index] %} INC {{ other }} {{ more[4-loop.index] }} ; {% endif %} ;;
{% endfor %}
{% endmacro %}
transpose_group:
    {{ init_bytes('LR6', 'LR7', [0,1,2,3], [4,5,6,7]) }}
    {{ init_bytes('LR8', 'LR9', [46,47,62,63], [110,111,126,127]) }}
    SET LR3 {{ cr.n_lane }}.H ; SET LR4 CR0 ; SET LR2 LR1 ;;
    ADDB LRD6 LR3 ; INC LR4 16 ;;
transpose_block:
    SET LR10 LR2 ;;
transpose_half:
    SET LR11 CR0 ; SET LR12 CR0 ; SET LR14 CR0 ;;
    DEC LR11 1 ; INC LR12 5 ; LD.MULT R0 LR10 {{ cr.vbase }} ;;
{% macro scatter(last) %}
{% for key in range(16) %}
    ADDBI LRD8 {{ -46 if key == 0 else 18 if key == 8 else 2 }} ;
    ADD LR10 LR10 {{ cr.stride }}.L ;
    {% if not last or key != 15 %} LD.MULT R0 LR10 {{ cr.vbase }} ; {% endif %}
    MULT.VE LR14 CR1 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD6 LRD8 0 ;
    {% if key == 15 %}
    INC LR11 1 ; ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR11 ;
    {% if not last %} BLT.S LR11 LR12 scatter_tile ; {% endif %}
    {% endif %} ;;
{% endfor %}
{% endmacro %}
scatter_tile:
    {{ scatter(false) }}
    {{ scatter(true) }}

    SET LR11 CR0 ; SET LR12 CR0 ; SET LR3 CR0 ; LD.MULT R0 LR14 {{ cr.panel }} ;;
    INC LR12 7 ; INC LR3 7 ; INC LR14 64 ;;
    SET LR15 CR0 ;;
rotate_tile:
    LD.MULT R1 LR11 {{ cr.panel }} ;;
    INC LR11 1 ; LD.MULT R0 LR11 {{ cr.panel }} ;
    MULT.VE LR14 CR1 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR12 ; INC LR12 1 ; BLT.S LR11 LR3 rotate_tile ;;

{% macro delta(reg, diff) %}{{ 'INC' if diff >= 0 else 'DEC' }} {{ reg }} {{ diff|abs }}{% endmacro %}
{% macro merge(upper) %}
{% set a = 0 if upper else 8 %}
{% set b = 9 if upper else 1 %}
    SET LR15 CR0 ; SET LR3 CR0 ; SET LR12 CR0 ;;
    INC LR15 128 ;;
    ADD LR5 LR15 LR15 ;;
    {% if a %} INC LR12 {{ a }} ; {% endif %} LD.MULT.CYCLIC LR12 {{ cr.panel }} LR3 ; ADD LR14 LR5 LR15 ;;
    {{ delta('LR12', b-a) }} ; LD.MULT.CYCLIC LR12 {{ cr.panel }} LR15 ; INC LR3 64 ;;
    {{ delta('LR12', a+2-b) }} ; LD.MULT.CYCLIC LR12 {{ cr.panel }} LR5 ; SET LR15 CR0 ;;
    {{ delta('LR12', b-a) }} ; LD.MULT.CYCLIC LR12 {{ cr.panel }} LR14 ; INC LR5 64 ; SET LR11 CR0 ;;
    {{ delta('LR12', a+4-b-2) }} ; LD.MULT R0 LR12 {{ cr.panel }} ; SET LR14 LR4 ;;
    {% if upper %} INC LR14 8 ;; {% endif %}
{% for col in range(4) %}
{% set h = 'on_inv' if col % 2 else 'on' %}
{% set v = 'on_inv' if col >= 2 else 'on' %}
    {{ delta('LR12', b-a) }} ; {% if col %} INC LR11 1 ; INC LR14 2 ; {% endif %} LD.MULT R1 LR12 {{ cr.panel }} ;
    MULT.RC.VE LR3 CR1 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ h }} {{ v }} LR11 ;;
    INC LR11 2 ; {{ delta('LR12', a+2-b) }} ; LD.MULT R0 LR12 {{ cr.panel }} ;
    MULT.VE LR3 CR1 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ h }} {{ v }} LR11 ;;
    DEC LR11 1 ; {{ delta('LR12', b-a) }} ; LD.MULT R1 LR12 {{ cr.panel }} ;
    MULT.RC.VE LR5 CR1 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ h }} {{ v }} LR11 ;;
    INC LR11 2 ; {{ delta('LR12', a-b-2) }} ; LD.MULT R0 LR12 {{ cr.panel }} ;
    MULT.VE LR3 CR1 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ h }} {{ v }} LR11 ;
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR14 ;;
{% endfor %}
{% endmacro %}
    {{ merge(false) }}
    {{ merge(true) }}
    SET LR3 CR0 ; INC LR4 1 ; INC LR15 128 ;;
    INC.MODP2 LR3 LR4 1 ;;
    BNE LR3 CR0 transpose_half ;;
    INC LR4 14 ; INC.MODP2 LR3 LR6 7 ;;
    SET LR12 {{ cr.k_count }}.H ;;
    ADD LR12 LR12 LR12 ;;
    INC LR12 16 ;;
    BEQ LR4 LR12 dot_group ;;
    INC LR3 8 ;;
    BLT.S LR3 LR15 transpose_advance ;;
    ADDBI LRD6 -120 ; INC LR2 1 ; B transpose_block ;;
transpose_advance:
    ADDBI LRD6 8 ; B transpose_block ;;

{# Cache the first value column in R1 and prefetch the next query. #}
dot_group:
    SET LR2 CR0 ; SET LR4 {{ cr.mh }}.H ; SET LR6 CR0 ;;
    INC LR2 16 ; SET LR7 CR1 ;;
    INC LR7 1 ;;
dot_head:
    SET LR5 {{ cr.mh }}.L ; LD.MULT R1 LR2 {{ cr.panel }} ;;
    LD.MULT.CYCLIC LR0 {{ cr.in0 }} LR6 ;;
dot_row:
    ADD LR9 LR2 CR1 ; ADD LR8 LR0 CR1 ; SET LR10 {{ cr.n_lane }}.L ; LD.MULT R0 LR9 {{ cr.panel }} ;;
    SET LR11 CR0 ; ADD LR0 LR0 {{ cr.stride }}.H ; LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR15 ;
    MULT.RC.VV LR6 R1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.ds }}.L ;
    BEQ LR10 LR7 dot_tail ;;
{% macro dot_next(test) %}
    INC LR9 1 ; LD.MULT R0 LR9 {{ cr.panel }} ;
    MULT.RC.VV LR15 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.ds }}.L ; DEC LR10 1 ;;
    INC LR9 1 ; INC LR11 1 ; LD.MULT R0 LR9 {{ cr.panel }} ;
    MULT.RC.VV LR6 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.ds }}.L ; {{ test }} ;;
{% endmacro %}
dot_second:
    {{ dot_next('BGT.S LR10 LR7 dot_second') }}
dot_tail:
    {{ dot_next('BEQ LR5 CR1 dot_last') }}
{% macro dot_store(prefetch) %}
    MULT.RC.VV LR15 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.ds }}.L ;
    {{ output() }} ; INC LR13 1 ;
    {% if prefetch %} DEC LR5 1 ; LD.MULT.CYCLIC LR0 {{ cr.in0 }} LR6 ; B dot_row ; {% endif %} ;;
{% endmacro %}
    {{ dot_store(true) }}
dot_last:
    {{ dot_store(false) }}
    ADD LR2 LR9 CR1 ; DEC LR4 1 ; BGT.S LR4 CR1 dot_head ;;
    B next_group ;;

{# Stream long reductions in 128-key chunks. #}
{% macro large_rows(tag, crossing, full=false) %}
{{ tag }}_row:
    SET LR7 LR2 ; SET LR12 {{ cr.k_count }}.L ;
    MULT.VE LR0 CR0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{{ tag }}_chunk:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR8 CR0 ; SET LR9 {{ 'LR10' if full else 'LR12' }} ;;
{% if not full %}
    BLT.S LR12 LR10 {{ tag }}_limit ;;
    SET LR9 LR10 ;;
{{ tag }}_limit:
{% endif %}
    INC LR5 1 ;
{% if not crossing %}
    LD.MULT.CYCLIC LR7 {{ cr.vbase }} LR0 ;
{% endif %}
    DEC LR9 1 ;;
{% if not crossing %}
    DEC LR8 1 ; {% if not full %} BEQ LR9 CR0 {{ tag }}_last ; {% endif %} ;;
{% endif %}
{{ tag }}_key:
{% if crossing %}
    LD.MULT.CYCLIC LR7 {{ cr.vbase }} LR0 ; ADD LR13 LR7 CR1 ;;
    LD.MULT.CYCLIC LR13 {{ cr.vbase }} LR10 ;;
{% else %}
    MULT.RC.VE LR3 LR8 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR7 {{ cr.vbase }} LR0 ; INC LR8 1 ; ADD LR7 LR7 {{ cr.stride }}.L ; DEC LR9 1 ; BGT.S LR9 CR1 {{ tag }}_key ;;
{{ tag }}_last:
{% endif %}
    MULT.RC.VE LR3 LR8 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;
{% if not crossing %}
    ADD LR7 LR7 {{ cr.stride }}.L ; INC LR8 1 ;
{% endif %}
    ;;
{% if crossing %}
    INC LR8 1 ; ADD LR7 LR7 {{ cr.stride }}.L ; DEC LR9 1 ; BGT.S LR9 CR0 {{ tag }}_key ;;
{% endif %}
{% if not crossing and not full %}
    DEC LR12 128 ; BEQ LR12 LR13 {{ tag }}_one ;;
{% else %}
    DEC LR12 128 ;;
{% endif %}
    BGT.S LR12 CR0 {{ tag }}_chunk ;;
{{ tag }}_store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; DEC LR11 1 ;;
    INC LR6 1 ; BNE LR11 CR0 {{ tag }}_row ;;
    B large_next_head ;;
{% if not crossing and not full %}
{{ tag }}_one:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR8 CR0 ;;
    LD.MULT.CYCLIC LR7 {{ cr.vbase }} LR0 ; INC LR5 1 ;;
    MULT.RC.VE LR3 LR8 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; B {{ tag }}_store ;;
{% endif %}
{% endmacro %}
large_entry:
    ADD LR12 LR15 LR15 ; INC.MODP2 LR3 CR0 3 ;;
    BNE LR14 LR12 large_setup ;;
    BNE LR3 CR0 large_setup ;;
    INC.MODP2 LR3 {{ cr.n_lane }}.L 1 ;;
    BNE LR3 CR0 large_setup ;;
    INC.MODP2 LR3 {{ cr.k_count }}.H 3 ;;
    BEQ LR3 CR0 transpose_group ;;
large_setup:
    SET LR10 LR15 ; SET LR15 {{ cr.n_lane }}.L ; SET LR13 CR0 ;;
large_group:
    SET LR2 LR1 ; SET LR3 {{ cr.n_lane }}.H ; SET LR4 {{ cr.mh }}.H ;;
large_head:
    SET LR11 {{ cr.mh }}.L ; SET LR14 LR3 ; SET LR13 LR10 ;;
    ADD LR14 LR14 LR15 ; INC LR13 1 ; SET LR8 CR0 ;;
    BGT.S LR14 LR10 large_split_row ;;
    INC.MODP2 LR8 {{ cr.k_count }}.L 7 ;;
    BEQ LR8 CR0 large_full_row ;;
    {{ large_rows('large_single', false) }}
    {{ large_rows('large_split', true) }}
    {{ large_rows('large_full', false, true) }}
large_next_head:
    DEC LR4 1 ; SET LR3 LR14 ;;
    BEQ LR4 CR0 large_next_group ;;
    BLT.S LR3 LR10 large_head ;;
    DEC LR3 128 ; INC LR2 1 ; B large_head ;;
large_next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.total_rows }} large_group ;;
    HALT ;;
