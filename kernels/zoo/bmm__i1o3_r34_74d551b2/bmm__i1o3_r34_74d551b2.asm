{# Each channel owns contiguous token chunks. Broadcast one query lane
   against a key vector, accumulating directly in output lane order. #}
{% macro mac(first, jump, condition) %}
    LD.MULT R0 LR10 {{ cr.in0 }} ; ADD LR11 LR11 {{ cr.stride }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR13 ; ADD LR10 LR10 {{ cr.stride }} ;;
    MULT.RC.VE LR13 LR7 0 LR13 {{ cr.widths }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; DEC LR12 1 ; {{ condition }} LR12 CR1 {{ jump }} ;;
{% endmacro %}
{% macro store(half) %}
    INC LR0 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.widths }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
    DEC LR0 1 ;;
group:
    SET LR2 LR1 ; ADD LR3 LR1 {{ cr.key_offset }} ; SET LR4 {{ cr.out0_d1 }} ;;
head:
    SET LR5 LR2 ; SET LR6 {{ cr.m }} ; SET LR7 CR0 ;;
row:
    SET LR8 LR3 ; SET LR9 {{ cr.tiles }} ;;
tile:
    SET LR10 LR5 ; SUB LR11 LR8 {{ cr.stride }} ; SET LR12 {{ cr.k }} ;;
    {{ mac(true, 'write', 'BEQ') }}
reduce:
    {{ mac(false, 'reduce', 'BNE') }}
write:
    DEC LR9 1 ; BEQ LR9 CR1 tail ;;
    {{ store('L') }}
    INC LR8 1 ; B tile ;;
tail:
    {{ store('H') }}
    DEC LR6 1 ; BEQ LR6 CR1 next_head ;;
    INC.MODP2 LR7 CR1 7 ;;
    BNE LR7 CR0 row ;;
    INC LR5 1 ; B row ;;
next_head:
    ADD LR2 LR2 {{ cr.head_step }} ; ADD LR3 LR3 {{ cr.head_step }} ; DEC LR4 1 ; BNE LR4 CR1 head ;;
    ADD LR1 LR1 {{ cr.group_step }} ; DEC LR14 1 ; BNE LR14 CR1 group ;;
    HALT ;;
