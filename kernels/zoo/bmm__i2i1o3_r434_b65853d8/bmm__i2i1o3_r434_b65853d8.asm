{# One accumulator row holds a query against one tile of keys. A supplies
   a scalar selected by the query lane; B supplies the whole key vector. #}
{% macro product(first) %}
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR15 ; DEC LR10 1 ;;
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR8 LR8 {{ cr.stride }}.L ; ADD LR9 LR9 {{ cr.stride }}.H ; {{ 'BEQ LR10 CR0 store' if first else 'BNE LR10 CR0 reduce' }} ;;
{% endmacro %}
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 {{ cr.b }} ;;
    SET LR15 CR0 ;;
group:
    SET LR4 {{ cr.in0_d1 }} ;;
head:
    SET LR12 {{ cr.in0_d1 }} ; SET LR7 {{ cr.m }} ;;
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
    {{ product(true) }}
reduce:
    {{ product(false) }}
store:
    INC LR11 1 ;;
    BEQ LR11 {{ cr.tiles }} tail ;;
    {{ output('L') }}
    B tile ;;
tail:
    {{ output('H') }}
    DEC LR7 1 ; ADD LR12 LR12 {{ cr.in0_d1 }} ;;
    BNE LR7 CR0 row ;;
next_head:
    DEC LR11 1 ; DEC LR3 1 ;;
    SUB LR1 LR9 LR11 ; DEC LR4 1 ; BEQ LR3 CR0 done ;;
    BNE LR4 CR0 head ;;
    ADD LR1 LR1 LR14 ; ADD LR0 LR0 LR13 ; B group ;;
done:
    HALT ;;
