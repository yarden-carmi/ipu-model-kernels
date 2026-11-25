{% macro store(mask) %}
    LD.MULT R0 LR1 {{ cr.in1 }} ; SET LR2 CR0 ; SET LR3 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

    INC LR13 128 ;;
plane:
    SET LR6 CR0 ; SET LR7 LR14 ; SET LR5 LR14 ;;
    SET LR12 {{ cr.width }} ; SET LR8 CR0 ;;
    INC LR8 {{ out0_d2 }} ;;
chunk:
    SET LR11 LR13 ; BNE LR12 CR1 gather ;;
    SET LR11 {{ cr.valid }}.L ;;
// The packed row traverses c fastest. The first view advances by A*B
// within c and starts each new b at flat offset a + A*b.
gather:
    BLT.S LR7 {{ cr.span }}.L locate ;;
    SUB LR7 LR7 {{ cr.span }}.L ; ADD LR6 LR6 {{ cr.span }}.H ; B gather ;;
locate:
{% if in0_d2 <= 128 %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ;;
{% elif in0_d2 <= 256 %}
    BLT.S LR7 LR13 low ; ADD LR10 LR6 CR1 ;;
    LD.MULT R0 LR10 {{ cr.in0 }} ; SUB LR9 LR7 LR13 ; B loaded ;;
low:
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ;;
loaded:
{% else %}
    SET LR10 LR6 ; SET LR9 LR7 ;;
physical_chunk:
    BLT.S LR9 LR13 load ;;
    INC LR10 1 ; DEC LR9 128 ; B physical_chunk ;;
load:
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% endif %}
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD2 0 ;
    ADD LR6 LR6 {{ cr.step_row }} ; ADD LR7 LR7 {{ cr.step_lane }} ; DEC LR8 1 ;;
    ADDBI LRD2 1 ; DEC LR11 1 ; BNE LR8 CR0 next_lane ;;
    ADD LR5 LR5 {{ cr.valid }}.H ; SET LR6 CR0 ; INC LR8 {{ out0_d2 }} ;;
    SET LR7 LR5 ;;
next_lane:
    BNE LR11 CR0 gather ;;
    DEC LR12 1 ; BEQ LR12 CR1 end_plane ;;
    {{ store('CR15.L') }}
    B chunk ;;
end_plane:
    {{ store(cr.tail ~ '.L') }}
    INC LR14 1 ; BGE.S {{ cr.last_row }} LR1 plane ;;
    HALT ;;
