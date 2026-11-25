{# LR0 is zero. LR8/LR5 walk the packed B columns across heads.
   LR13 is the first A row for the current head, and LR9 is the output cursor. #}
{% macro mac(first) %}
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR11 {{ cr.in1 }} ;;
    MULT.RC.VE LR0 LR5 0 LR0 {{ cr.ds_rows }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR10 LR10 {{ cr.a_stride }} ; ADD LR11 LR11 {{ cr.b_stride }} ; DEC LR12 1 ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_rows }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; SET LR13 CR0 ;;
group:
    SET LR2 CR0 ; SET LR5 CR0 ;;
head:
    SET LR3 CR0 ;;
column:
    SET LR6 CR0 ; SET LR7 LR13 ;;
tile:
    SET LR10 LR7 ; SET LR11 LR8 ; SET LR12 {{ cr.k }} ;;
    {{ mac(true) }}
    BZ LR12 reduced ;;
reduce:
    {{ mac(false) }}
    BNZ LR12 reduce ;;
reduced:
    INC LR6 1 ;;
    BGE.S LR6 {{ cr.tiles }} tail ;;
    {{ store('L') }}
    INC LR7 1 ; INC LR9 1 ; B tile ;;
tail:
    {{ store('H') }}
    INC LR9 1 ; INC LR3 1 ;;
    INC.MODP2 LR5 CR1 7 ;;
    BNZ LR5 same_chunk ;;
    INC LR8 1 ;;
same_chunk:
    BLT.S LR3 {{ cr.n }} column ;;
    ADD LR13 LR13 {{ cr.tiles }} ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.b }} head ;;
    ADD LR13 LR13 {{ cr.a_skip }} ; INC LR1 1 ;;
    SUB LR8 LR11 {{ cr.b_stride }} ;;
    INC LR8 1 ; BLT.S LR1 LR15 group ;;
    HALT ;;
