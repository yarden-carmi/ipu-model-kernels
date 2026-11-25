{# LR1 streams input; LR6 walks the output's [d0,d3,d1,chunk] order
   at the same logical coordinates; LR7 holds the plane's first output row. #}
{% macro add_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ; INC LR1 1 ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; INC LR3 1 ;;
    INC LR6 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; SET LR3 CR0 ; SET LR7 CR0 ;;
    SET LR5 CR1 ; SET LR10 {{ cr.in0_d0 }} ;;
batch:
    SET LR9 {{ cr.in0_d1 }} ;;
plane:
    SET LR6 LR7 ; SET LR8 {{ cr.in0_d3 }} ;;
column:
    SET LR4 {{ cr.chunks }} ; BEQ {{ cr.chunks }} LR5 tail ;;
chunk:
    {{ add_row(cr.full ~ '.L') }}
    DEC LR4 1 ;;
    BNE LR4 LR5 chunk ;;
tail:
    {{ add_row(cr.tail ~ '.L') }}
    DEC LR8 1 ;;
    BEQ LR8 CR0 plane_end ;;
    ADD LR6 LR6 {{ cr.gap }} ; B column ;;
plane_end:
    BNE LR3 {{ cr.operand_rows }} next_plane ;;
    SET LR3 CR0 ;;
next_plane:
    DEC LR9 1 ; ADD LR7 LR7 {{ cr.chunks }} ;;
    BNE LR9 CR0 plane ;;
    SET LR7 LR6 ; DEC LR10 1 ;;
    BNE LR10 CR0 batch ;;
    HALT ;;
