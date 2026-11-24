{# NCHW view over row-aligned storage. Start the cyclic vector at the
   current spatial x offset so its low lanes are this output row. #}
{% macro mac(src, first=false, advance=false) %}
    MULT.RC.VE LR14 {{ src }} 0 LR0 {{ cr.store_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% if advance %} ; INC LR3 1{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR14 CR0 ; SET LR15 CR0 ;;
    SET LR9 {{ cr.out0_d0 }} ; INC LR15 128 ; DEC LR5 1 ;;
batch:
    SET LR10 LR6 ;;
stripe:
    SET LR11 {{ cr.n }} ; SET LR12 CR0 ;;
    DEC LR12 1 ;;
channel:
    MULT.EE LR0 CR0 0 LR0 {{ cr.store_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR13 {{ cr.planes }} ;;
plane:
    LD.MULT R0 LR12 {{ cr.coeff }} ; INC LR12 1 ; SUB LR2 LR8 {{ cr.spatial }} ; SET LR1 {{ cr.chunks }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.store_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
chunk:
    LD.MULT R0 LR12 {{ cr.coeff }} ; INC LR12 1 ; DEC LR1 1 ; SET LR3 CR0 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.spatial }} ; DEC LR3 1 ; SET LR7 LR15 ; BNE LR1 CR0 full_chunk ;;
    SET LR7 {{ cr.tail }} ;;
full_chunk:
    BEQ LR7 CR1 final_lane ;;
    DEC LR7 3 ;;
lane:
    {{ mac('LR3', advance=true) }} ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.spatial }} ; BLT.S LR3 LR7 lane ;;
final_lane:
    {{ mac('LR3', advance=true) }} ; BNE LR1 CR0 chunk ;;
    DEC LR13 1 ;;
    BNE LR13 CR0 plane ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.store_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; DEC LR11 1 ;;
    BNE LR11 CR0 channel ;;
    ADD LR14 LR14 {{ cr.out0_d3 }} ; DEC LR10 1 ;;
    BNE LR14 LR15 next_stripe ;;
    SET LR14 CR0 ; INC LR8 1 ;;
next_stripe:
    BNE LR10 CR0 stripe ;;
    ADD LR8 LR8 {{ cr.batch_gap }} ; DEC LR9 1 ;;
    BNE LR9 CR0 batch ;;
    HALT ;;
