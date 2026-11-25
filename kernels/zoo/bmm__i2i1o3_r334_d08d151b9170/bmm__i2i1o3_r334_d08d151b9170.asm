{# The transposed heads view packs adjacent reduction positions, not
   adjacent output columns. Each half-row supplies an entire N vector. #}
{% macro mac(slot) %}
    MULT.RC.VE {{ slot }} LR14 0 LR13 {{ cr.outdesc }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;
    DEC LR15 1 ; BEQ LR15 CR1 emit ;;
{% endmacro %}
{% macro advance(lab) %}
    INC.MODP2 LR14 CR1 7 ;;
    BNE LR14 CR0 {{ lab }} ;;
    INC LR12 1 ; LD.MULT R0 LR12 {{ cr.in0 }} ;;
{% endmacro %}

    SET LR2 CR0 ; SET LR3 CR0 ; SET LR7 {{ cr.out0_d0 }} ;;
    SET LR8 CR0 ; SET LR13 CR0 ; SET LR1 {{ cr.in1_d1 }} ;;
    DEC LR8 1 ;;
group:
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 {{ cr.out0_d1 }} ;;
head:
    SET LR9 LR2 ; SET LR10 {{ cr.m }} ;;
query_row:
    SET LR11 LR3 ; SET LR12 LR9 ; SET LR14 LR4 ;;
    SET LR15 {{ cr.k }} ; LD.MULT R0 LR12 {{ cr.in0 }} ;;
    MULT.VE LR13 CR0 0 LR13 {{ cr.outdesc }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR13 ; BNE LR5 CR0 odd ;;
even:
    {{ mac('LR13') }}
    {{ advance('odd') }}
odd:
    {{ mac('LR1') }}
    INC LR11 1 ; LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR13 ;;
    {{ advance('even') }}
    B even ;;
emit:
    INC LR8 1 ; ADD LR9 LR9 {{ cr.arows }} ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.outdesc }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
    DEC LR10 1 ; BNE LR10 CR1 query_row ;;

    ADD LR4 LR4 {{ cr.k }} ; SET LR12 CR0 ;;
    INC LR12 128 ;;
    BLT.S LR4 LR12 advance_keys ;;
    DEC LR4 128 ; INC LR2 1 ;;
advance_keys:
    {% if k//2 %} INC LR3 {{ k//2 }} ;; {% endif %}
    {% if k%2 %}
    BEQ LR5 CR0 set_odd ;;
    SET LR5 CR0 ; INC LR3 1 ; B next_head ;;
set_odd:
    SET LR5 CR1 ;;
next_head:
    {% endif %}
    DEC LR6 1 ; BNE LR6 CR1 head ;;
    ADD LR2 LR2 LR0 ; ADD LR3 LR3 {{ cr.bgap }} ; DEC LR7 1 ; BNE LR7 CR1 group ;;
    HALT ;;
