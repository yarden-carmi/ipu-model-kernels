{# Build a cyclic vector of 2^-3 in the input format. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR9 CR0 ;;
    MULT.VE LR9 CR0 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR9 ;;
    LD.MULT R0 LR9 {{ cr.tmp }} ;;
{% for _ in range(3) %}
    MULT.VE LR9 CR1 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
{% endfor %}
    ACTIVATE.QUANTIZE exp2 {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR9 ;;
    LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR9 ;;
plane:
    SET LR2 CR0 ; SET LR10 LR1 ; SET LR11 CR0 ;;
column:
    SET LR4 LR10 ; SET LR7 CR0 ;;
tile:
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR6 CR0 ;;
    INC LR7 1 ;;
    SET LR8 CR0 ;;
    BEQ LR7 {{ cr.oc }} tail_count ;;
    INC LR8 128 ;;
    B gather ;;
tail_count:
    SET LR8 {{ cr.last }} ;;
gather:
    MULT.VE LR9 CR0 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
lane:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.RC.VE LR9 LR11 0 LR9 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD12 LRD12 7 ;;
    ADDBI LRD12 1 ; ADD LR4 LR4 {{ cr.ic }} ; INC LR6 1 ;;
    BLT.S LR6 LR8 lane ;;
    BEQ LR7 {{ cr.oc }} tail_store ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
    B tile ;;
tail_store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; INC LR2 1 ; INC.MODP2 LR11 CR1 7 ;;
    BNE LR11 CR0 same_chunk ;;
    INC LR10 1 ;;
same_chunk:
    BLT.S LR2 {{ cr.w }} column ;;
    ADD LR1 LR1 {{ cr.plane_rows }} ; INC LR0 1 ;;
    BLT.S LR0 {{ cr.planes }} plane ;;
    HALT ;;
