{% macro start_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

    INC LR8 128 ;;
batch:
    # View offset for (batch, b, c) is batch + d0 * (b + d1 * c).
    SET LR5 CR0 ; SET LR7 LR9 ; SET LR11 LR9 ;;
    SET LR10 {{ cr.out0_d2 }} ;;
column:
    SET LR2 {{ cr.chunks }} ;;
row:
    SET LR3 LR8 ; SET LR4 CR0 ;
    BEQ LR2 CR1 start_tail ;;
    {{ start_row('CR15.L') }}
    B gather ;;
start_tail:
    SET LR3 {{ cr.tail }} ;;
    {{ start_row(cr.tail_ds ~ '.L') }}
gather:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR7 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR4 {{ cr.one }}.L ;;
    ADD LR7 LR7 {{ cr.out0_d0 }} ; ADD LR11 LR11 {{ cr.out0_d0 }} ; INC LR4 1 ;;
source_column:
    # Skip the physical padding after each stored innermost dimension.
    BLT.S LR11 {{ cr.in0_d2 }} source_row ;;
    SUB LR11 LR11 {{ cr.in0_d2 }} ; ADD LR7 LR7 LR15 ; B source_column ;;
source_row:
    BLT.S LR7 LR8 check ;;
    DEC LR7 128 ; INC LR5 1 ; B source_row ;;
check:
    BLT.S LR4 LR3 gather ;;
    BEQ LR2 CR1 tail ;;
    {{ store('CR15.L') }}
    INC LR1 1 ; DEC LR2 1 ; B row ;;
tail:
    {{ store(cr.tail_ds ~ '.L') }}
    INC LR1 1 ; DEC LR10 1 ;;
    BNE LR10 CR0 column ;;
    INC LR9 1 ;;
    BLT.S LR9 {{ cr.out0_d0 }} batch ;;
    HALT ;;
