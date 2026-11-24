{# Each vector holds 128 query rows. Keep a key chunk of RHS scalars
   in R0, and pipeline the next A vector into the cyclic registers. #}
{% macro mac(prefetch) %}
    MULT.RC.VE LR14 LR12 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR12 1
    {%- if prefetch %} ; ADD LR8 LR8 {{ cr.stride }}.H ; LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR14 ; DEC LR3 1 ; BGT.S LR3 LR11 key{% endif %} ;;
{% endmacro %}
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endmacro %}
    INC LR15 128 ; INC LR11 2 ;;
group:
    SET LR4 {{ cr.mh }}.H ;;
head:
    SET LR5 {{ cr.n }} ;;
column:
    SET LR2 LR0 ; SET LR6 {{ cr.mh }}.L ;;
tile:
    SET LR8 LR2 ; SET LR9 LR7 ; SET LR10 {{ cr.k }} ;;
    MULT.VE LR14 CR0 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
chunk:
    SET LR3 LR10 ; BLE.S LR10 LR15 chunk_ready ;;
    SET LR3 LR15 ;;
chunk_ready:
    LD.MULT R0 LR9 {{ cr.in1 }} ; SUB LR10 LR10 LR3 ; SET LR12 CR0 ;;
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR14 ; DEC LR12 1 ; BEQ LR3 CR1 drain ;;
key:
    {{ mac(true) }}
drain:
    {{ mac(false) }}
    BEQ LR10 CR0 store ;;
    ADD LR8 LR8 {{ cr.stride }}.H ; INC LR9 1 ; B chunk ;;
store:
    BGT.S LR6 LR15 full ;;
    {{ output('H') }}
    ADD LR7 LR7 {{ cr.stride }}.L ; DEC LR5 1 ; BGT.S LR5 CR1 column ;;
    ADD LR0 LR0 {{ cr.astride }} ; DEC LR4 1 ; BGT.S LR4 CR1 head ;;
    ADD LR7 LR7 {{ cr.correction }} ; DEC LR1 1 ; BGT.S LR1 CR1 group ;;
    HALT ;;
full:
    {{ output('L') }}
    DEC LR6 128 ; INC LR2 1 ; B tile ;;
