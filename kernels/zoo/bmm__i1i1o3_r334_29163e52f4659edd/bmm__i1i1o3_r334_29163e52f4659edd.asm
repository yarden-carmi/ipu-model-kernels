{% macro mac(slot, lane, first=false) -%}
    MULT.RC.VE {{ slot }} {{ lane }} 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }}
{%- endmacro %}
{% macro store(ds, addr) -%}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} {{ addr }}
{%- endmacro %}

    SET LR5 {{ cr.arows }} ; SET LR7 {{ cr.nchunks }} ;;
    BNE LR5 CR1 general ;;
    BNE LR7 CR1 general ;;
    SET LR9 {{ cr.k }} ; SET LR0 CR0 ; SET LR1 CR0 ;;
    SET LR3 CR0 ;;
    INC LR3 128 ;;
    ADD LR4 LR3 LR3 ;;
    ADD LR6 LR4 LR3 ;;
    SET LR8 {{ cr.m }} ; SET LR2 CR0 ; SET LR10 CR0 ;;
    DEC LR8 1 ; DEC LR10 1 ; SET LR15 CR0 ;;
    INC LR15 3 ;;
    BLE.S LR9 LR15 general ;;

{# Single chunk: keep the first A row and first three B rows resident. #}
cached_head:
    SET LR5 LR1 ; SET LR7 LR1 ; SET LR13 CR0 ; LD.MULT R1 LR1 {{ cr.in0 }} ;;
    DEC LR13 1 ; SET LR12 LR3 ; ADD LR9 LR1 {{ cr.k }} ; LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR3 ;;
    INC LR7 1 ; DEC LR12 1 ; DEC LR9 1 ; LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR4 ;;
    INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR6 ;;
    SET LR14 LR7 ;;
cached_row:
    INC LR13 1 ; INC LR12 1 ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; {{ mac('LR3', 'LR12', true) }} ;;
    INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; {{ mac('LR4', 'LR13') }} ;;
    INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ; {{ mac('LR6', 'LR13') }} ;;
cached_a:
    INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; BEQ LR7 LR9 cached_store ;;
    INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ; {{ mac('LR0', 'LR13') }} ; B cached_a ;;
cached_store:
    SET LR5 LR1 ; SET LR7 LR14 ; INC LR10 1 ; {{ mac('LR0', 'LR13') }} ; {{ store(cr.dstail, 'LR10') }} ; BLT.S LR13 LR8 cached_row ;;
    INC LR2 1 ; ADD LR1 LR1 {{ cr.k }} ;;
    BLT.S LR2 {{ cr.b }} cached_head ;;
    HALT ;;

{# Multi-chunk: each K step skips all the sequence chunks in that input.
   MULT reads the current pair before the next A load overwrites R0. #}
{% macro tiled_mac(first, preload, jump='') %}
    {{ mac('LR0', 'LR13', first) }} ; {% if preload %}ADD LR12 LR12 {{ cr.arows }} ; LD.MULT R0 LR12 {{ cr.in0 }} ; DEC LR9 1 ; {% endif %}{% if jump %}B {{ jump }} ; {% endif %};;
{% endmacro %}
general:
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ;;
head:
    SET LR4 CR0 ; SET LR5 LR1 ; SET LR13 CR0 ;;
row:
    SET LR6 CR0 ;;
tile:
    ADD LR7 LR2 LR6 ; SET LR9 {{ cr.k }} ; SET LR12 LR5 ;;
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ; BEQ LR9 CR1 single ;;
    {{ tiled_mac(true, true) }}
next_b:
    ADD LR7 LR7 {{ cr.nchunks }} ; LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ; BNE LR9 CR1 inner ;;
    {{ tiled_mac(false, false) }}
store_tile:
    INC LR6 1 ;;
    BEQ LR6 {{ cr.nchunks }} tail ;;
    {{ store(cr.dsfull, 'LR10') }} ;;
    INC LR10 1 ;;
    B tile ;;
tail:
    {{ store(cr.dstail, 'LR10') }} ;;
    INC LR10 1 ; INC LR4 1 ; INC.MODP2 LR13 CR1 7 ;;
    BNE LR13 CR0 same_row ;;
    INC LR5 1 ;;
same_row:
    BLT.S LR4 {{ cr.m }} row ;;
    SET LR12 CR0 ;;
head_stride:
    ADD LR1 LR1 {{ cr.arows }} ; ADD LR2 LR2 {{ cr.nchunks }} ; INC LR12 1 ;;
    BLT.S LR12 {{ cr.k }} head_stride ;;
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.b }} head ;;
    HALT ;;
inner:
    {{ tiled_mac(false, true, 'next_b') }}
single:
    {{ tiled_mac(true, false, 'store_tile') }}
