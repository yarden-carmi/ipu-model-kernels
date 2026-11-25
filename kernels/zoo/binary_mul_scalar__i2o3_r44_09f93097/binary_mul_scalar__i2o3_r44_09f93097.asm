{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% macro coefficient(value, acc) %}
    MULT.VE LR0 {{ value }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    {{ coefficient('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ coefficient(cr.fp_hi, 'ADD.FIRST') }}
    {{ coefficient(cr.fp_lo, 'SUB') }}
    {{ coefficient(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;

# Gather two adjacent input lanes from each column into one packed row.
plane:
    SET LR10 LR1 ; SET LR2 {{ cr.pairs }} ; SET LR11 CR0 ;;
chunk:
    SET LR6 CR0 ; SET LR7 {{ cr.src_pair }} ;;
pair:
    SET LR4 LR10 ; SET LR5 LR14 ; SET LR8 CR0 ;;
    SET LR9 {{ cr.dst_pair }} ;;
column:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.RESHAPE LRD6 LRD8 6 ; DEC LR5 1 ; ADD LR4 LR4 {{ cr.chunks }} ;;
    ADDBI LRD8 1 ; BNE LR5 CR0 column ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; DEC LR2 1 ; INC.MODP2 LR11 CR1 6 ;;
    BEQ LR2 CR0 next_plane ;;
    ADDBI LRD6 2 ; BNE LR11 CR0 pair ;;
    INC LR10 1 ; B chunk ;;
next_plane:
    ADD LR1 LR1 {{ cr.plane_rows }} ;;
    BLT.S LR1 LR15 plane ;;
    HALT ;;
