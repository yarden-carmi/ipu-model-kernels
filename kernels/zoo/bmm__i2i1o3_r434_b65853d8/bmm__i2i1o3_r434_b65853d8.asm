{# One accumulator row holds a query against one tile of keys. A supplies
   a scalar selected by the query lane; B supplies the whole key vector. #}
{% macro output(half) %}
    INC LR2 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{% endmacro %}
    SET LR0 CR0 ; SET LR15 CR0 ; SET LR3 {{ cr.b }} ;;
    SUB LR2 LR0 CR1 ; SET LR11 CR0 ; BEQ LR6 CR0 aligned_check ;;
group:
    SET LR4 {{ cr.heads_lanes }}.L ;;
head:
    SET LR12 {{ cr.heads_lanes }}.L ; SET LR7 {{ cr.m }} ;;
    SUB LR12 LR12 LR4 ;;
row:
    {# The query view is token-major in storage: flat pair = token*H+head.
       Unflatten it into the stored tensor's (head, token) coordinates. #}
    SET LR5 LR12 ; SET LR6 LR0 ;;
query_head:
    BLT.S LR5 {{ cr.m }} query_chunk ;;
    SUB LR5 LR5 {{ cr.m }} ; ADD LR6 LR6 {{ cr.head_rows }} ; B query_head ;;
query_chunk:
    SET LR8 CR0 ;;
    INC LR8 128 ;;
chunk_loop:
    BLT.S LR5 LR8 query_ready ;;
    DEC LR5 128 ; INC LR6 1 ; B chunk_loop ;;
query_ready:
    SET LR11 CR0 ;;
tile:
    SET LR8 LR6 ; ADD LR9 LR1 LR11 ; SET LR10 {{ cr.k }} ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR15 ; DEC LR10 1 ; ADD LR8 LR8 {{ cr.stride }}.L ;;
    DEC LR10 1 ; BEQ LR10 CR0 only_one ;;
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR8 {{ cr.in0 }} ; ADD LR9 LR9 {{ cr.stride }}.H ;;
reduce:
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR15 ; DEC LR10 1 ; ADD LR8 LR8 {{ cr.stride }}.L ; INC LR5 128 ; BEQ LR10 CR0 last1 ;;
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.in0 }} ; ADD LR9 LR9 {{ cr.stride }}.H ;;
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR15 ; DEC LR10 1 ; ADD LR8 LR8 {{ cr.stride }}.L ; DEC LR5 128 ; BEQ LR10 CR0 last0 ;;
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; LD.MULT R1 LR8 {{ cr.in0 }} ; ADD LR9 LR9 {{ cr.stride }}.H ; B reduce ;;
last1:
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ADD LR9 LR9 {{ cr.stride }}.H ; B restore ;;
last0:
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ADD LR9 LR9 {{ cr.stride }}.H ; B store ;;
restore:
    DEC LR5 128 ; B store ;;
only_one:
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ADD LR9 LR9 {{ cr.stride }}.H ;;
store:
    INC LR11 1 ;;
    BEQ LR11 {{ cr.tile_chunks }}.L tail ;;
    {{ output('L') }} ; B tile ;;
tail:
    {{ output('H') }} ; DEC LR7 1 ; ADD LR12 LR12 {{ cr.heads_lanes }}.L ;;
    BNE LR7 CR0 row ;;
next_head:
    DEC LR11 1 ; DEC LR3 1 ;;
    SUB LR1 LR9 LR11 ; DEC LR4 1 ; BEQ LR3 CR0 done ;;
    BNE LR4 CR0 head ;;
    ADD LR1 LR1 LR14 ; ADD LR0 LR0 LR13 ; B group ;;
done:
    HALT ;;

{# Two loads per K step. Each MAC issues the next A load; the
   intervening word loads B and advances the A address. Keep the scalar
   selectors for R0 and R1 live for the entire reduction. #}
{% macro mac(scalar, first=false) %}
    MULT.RC.VE LR15 {{ scalar }} 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }}
{%- endmacro %}
{% macro aligned_tile(tag, half, second) %}
    SET LR8 LR6 ; SET LR10 {{ cr.k }} ; ADD LR12 LR5 {{ cr.heads_lanes }}.H ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
    {% if second %}ADD LR9 LR1 CR1{% else %}SET LR9 LR1{% endif %} ; ADD LR8 LR8 {{ cr.stride }}.L ; LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR15 ;;
    {{ mac('LR5', true) }} ; LD.MULT R1 LR8 {{ cr.in0 }} ; ADD LR9 LR9 {{ cr.stride }}.H ; DEC LR10 2 ;;
{{ tag }}_odd:
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR15 ; ADD LR8 LR8 {{ cr.stride }}.L ; BEQ LR10 CR0 {{ tag }}_last ;;
    {{ mac('LR12') }} ; LD.MULT R0 LR8 {{ cr.in0 }} ; ADD LR9 LR9 {{ cr.stride }}.H ;;
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR15 ; ADD LR8 LR8 {{ cr.stride }}.L ;;
    {{ mac('LR5') }} ; LD.MULT R1 LR8 {{ cr.in0 }} ; ADD LR9 LR9 {{ cr.stride }}.H ; DEC LR10 2 ; B {{ tag }}_odd ;;
{{ tag }}_last:
    {{ mac('LR12') }} ; {{ output(half) }} ;;
{% endmacro %}

aligned_check:
    INC LR11 2 ;;
    BNE LR11 {{ cr.tile_chunks }}.L group ;;
{# The transposed query view walks every Hth lane for one logical
   head. On aligned chunks the lane phase is constant across chunks. #}
aligned_group:
    SET LR4 {{ cr.heads_lanes }}.L ;;
aligned_head:
    SET LR6 LR0 ; SET LR7 {{ cr.heads_lanes }}.L ;;
aligned_physical_head:
    SET LR11 {{ cr.tile_chunks }}.H ;;
aligned_chunk:
    SET LR5 {{ cr.heads_lanes }}.L ;;
    SUB LR5 LR5 LR4 ;;
aligned_row:
    {{ aligned_tile('left', 'L', false) }}
    {{ aligned_tile('right', 'H', true) }}
    ADD LR5 LR5 {{ cr.heads_lanes }}.L ;;
    BLT.S LR5 {{ cr.heads_lanes }}.H aligned_row ;;
    INC LR6 1 ; DEC LR11 1 ; BGT.S LR11 CR1 aligned_chunk ;;
    SUB LR6 LR6 {{ cr.tile_chunks }}.H ; DEC LR7 1 ; BLE.S LR7 CR1 aligned_head_end ;;
    ADD LR6 LR6 {{ cr.head_rows }} ; B aligned_physical_head ;;
aligned_head_end:
    ADD LR1 LR9 {{ cr.stride }}.H ; DEC LR3 1 ; BEQ LR3 CR1 done ;;
    DEC LR1 1 ; DEC LR4 1 ; BGT.S LR4 CR1 aligned_head ;;
    ADD LR1 LR1 LR14 ; ADD LR0 LR0 LR13 ; B aligned_group ;;
