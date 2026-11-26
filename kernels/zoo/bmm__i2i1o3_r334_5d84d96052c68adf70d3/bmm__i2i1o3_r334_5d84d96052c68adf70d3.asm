{# RHS rows are vectors of output columns, with column tiles interleaved across keys. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR14 CR0 ; SET LR15 CR0 ; DEC LR2 1 ;;
    INC LR15 128 ;;
group:
    SET LR4 CR0 ; SET LR5 {{ cr.keys_heads }}.H ;;
head:
    SET LR6 {{ cr.rows_tiles }}.L ;;
    ADD LR13 LR4 {{ cr.keys_heads }}.L ; SET LR11 {{ cr.keys_heads }}.L ;;
    DEC LR11 2 ; BGT.S LR13 LR15 row ;;
    BLE.S LR11 CR0 row ;;
    DEC LR13 3 ; B resident_row ;;
row:
    SET LR7 {{ cr.rows_tiles }}.H ; SET LR8 LR1 ;;
tile:
    SET LR9 LR8 ; SET LR10 LR0 ; SET LR11 {{ cr.keys_heads }}.L ;;
    SET LR12 LR4 ;;

{% macro chunk_setup(tag) %}
{{ tag }}:
    ADD LR13 LR12 LR11 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
    BLE.S LR13 LR15 {{ tag }}_bound ;;
    SET LR13 LR15 ;;
{{ tag }}_bound:
    ADD LR11 LR11 LR12 ;;
    SUB LR11 LR11 LR13 ; DEC LR13 3 ; DEC LR12 1 ;;
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ;;
{%- endmacro %}

{% macro mac(first=false) %}
    MULT.RC.VE LR14 LR12 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; INC LR12 1 ; ADD LR9 LR9 {{ cr.rows_tiles }}.H
{%- endmacro %}

    {{ chunk_setup('first_chunk') }}
    BGT.S LR12 LR13 first_single ;;
    {{ mac(true) }} ; LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ; BLT.S LR12 LR13 key ;;
    B last_key ;;
first_single:
    {{ mac(true) }} ; B chunk_end ;;
    {{ chunk_setup('next_chunk') }}
    BGT.S LR12 LR13 last_key ;;
key:
    {{ mac() }} ; LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ; BLT.S LR12 LR13 key ;;
last_key:
    {{ mac() }} ;;
chunk_end:
    INC LR12 1 ; BEQ LR11 CR0 store ;;
    INC LR10 1 ; SET LR12 CR0 ; B next_chunk ;;

store:
    BLE.S LR7 CR1 last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ; DEC LR7 1 ; INC LR8 1 ; B tile ;;
last_tile:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ; DEC LR6 1 ;;
    BEQ LR6 CR0 head_end ;;
    ADD LR0 LR0 {{ cr.a_stride }} ; B row ;;

{# When a head fits in one A row, keep that row resident across all N tiles. #}
resident_row:
    LD.MULT R0 LR0 {{ cr.in0 }} ; SET LR8 LR1 ; SET LR7 {{ cr.rows_tiles }}.H ;;
resident_tile:
    SET LR9 LR8 ; SUB LR12 LR4 CR1 ; LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ; BLE.S LR7 CR1 resident_tail ;;
{% macro resident_keys(tag) %}
    {{ mac(true) }} ; LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ;;
{{ tag }}:
    {{ mac() }} ; LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ; BLT.S LR12 LR13 {{ tag }} ;;
{%- endmacro %}
    {{ resident_keys('resident_full_keys') }}
    {# LR9 is dead on the last key, freeing an LR slot for output addressing. #}
    MULT.RC.VE LR14 LR12 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR12 1 ; INC LR2 1 ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    DEC LR7 1 ; INC LR8 1 ; B resident_tile ;;
resident_tail:
    {{ resident_keys('resident_tail_keys') }}
    MULT.RC.VE LR14 LR12 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR12 1 ; INC LR2 1 ; DEC LR6 1 ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    BEQ LR6 CR0 resident_end ;;
    ADD LR0 LR0 {{ cr.a_stride }} ; B resident_row ;;
resident_end:
    SET LR10 LR0 ; INC LR12 1 ;;
head_end:
    SUB LR0 LR10 {{ cr.a_rewind }} ; SET LR4 LR12 ; ADD LR1 LR1 {{ cr.rhs_head }} ;;
    DEC LR5 1 ;;
    BNE LR4 LR15 head_normalized ;;
    INC LR0 1 ; SET LR4 CR0 ;;
head_normalized:
    BGT.S LR5 CR0 head ;;
    ADD LR0 LR0 {{ cr.a_gap }} ; ADD LR1 LR1 {{ cr.b_gap }} ; DEC LR3 1 ; BGT.S LR3 CR1 group ;;
    HALT ;;
