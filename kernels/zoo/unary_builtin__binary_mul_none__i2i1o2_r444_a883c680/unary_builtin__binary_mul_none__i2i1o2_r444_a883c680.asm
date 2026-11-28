{% macro scalar(index, factor, qf, acc) %}
    MULT.EE {{ index }} {{ factor }} 0 LR0 {{ cr.full }}.L {{ qf }}.L ; ACC.{{ acc }}
{% endmacro %}
{% macro save(act, qf, slot, base=cr.s0, ds='.L') %}
    ; ACTIVATE.QUANTIZE {{ act }} {{ cr.full }}{{ ds }} {{ qf }}.L {{ base }} {{ slot }}
{% endmacro %}
    INC LR8 128 ; INC LR3 1 ; INC LR4 2 ;;
    {{ scalar('LR0', 'CR0', cr.qf_in1, 'ADD.FIRST') }} {{ save('exp2', cr.qf_in0, 'LR0') }} ;;
    LD.MULT R1 LR0 {{ cr.s0 }} ; INC LR9 8 ;;
reciprocal:
    LD.MULT R0 LR2 {{ cr.in1 }} ;;
    {{ scalar('LR0', cr.two, cr.qf_in1, 'ADD.FIRST') }} {{ save(act_s0, cr.qf_in0, 'LR9') }} ;;
    {{ scalar('LR0', cr.factor, cr.qf_in1, 'ADD.FIRST') }} {{ save(act_s0, cr.qf_in0, 'LR0') }} ;;
    LD.MULT R0 LR0 {{ cr.s0 }} ;;
{% for slot, acc in [('LR3', 'ADD.FIRST'), ('LR4', 'SUB.FIRST')] %}
    {{ scalar('LR0', 'CR1', cr.qf_in0, acc) }} ;;
    {{ scalar('LR8', cr.zero_threshold, cr.qf_in0, 'SUB') }} {{ save('relu', cr.qf_in0, slot) }} ;;
{% endfor %}
    LD.MULT R0 LR3 {{ cr.s0 }} ;;
    {{ scalar('LR0', cr.restore, cr.qf_in0, 'ADD.FIRST') }} ; LD.MULT R0 LR4 {{ cr.s0 }} ;;
    {{ scalar('LR0', cr.restore, cr.qf_in0, 'SUB') }} ; LD.MULT R0 LR9 {{ cr.s0 }} ;;
    {{ scalar('LR0', 'CR1', cr.qf_in0, 'ADD') }} {{ save('identity', cr.qf_in0, 'LR9') }} ;;
    INC LR9 1 ; INC LR2 1 ;;
    BLT.S LR2 LR14 reciprocal ;;

    SET LR9 LR10 ; INC LR11 8 ; DEC LR13 1 ;;
    INC LR5 3 ; SET LR14 CR0 ;;
    INC LR14 4 ;;
batch:
    SET LR2 LR11 ; SET LR3 CR0 ;;
channel:
    SET LR2 LR11 ; SET LR3 CR0 ;;
row:
    SET LR4 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.s0 }} LR0 ;;
lane:
    MULT.RC.VE LR0 LR4 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD6 7 ; BLT.S LR4 LR13 next_lane ;;
    BEQ LR0 LR0 row_store ;;
next_lane:
    INC LR4 1 ; ADDBI LRD6 1 ; INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.s0 }} LR0 ; BEQ LR0 LR0 lane ;;
row_store:
    ACTIVATE.QUANTIZE identity {{ cr.full }}.H {{ cr.qf_out0 }}.L {{ cr.s0 }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.s0 }} LR0 ; INC LR2 1 ; INC LR3 1 ;;
{% for sign, slot in [('SUB.FIRST','LR5'), ('ADD.FIRST','LR14')] %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.H {{ cr.qf_out0 }}.L ; ACC.{{ sign }} ;;
    {{ scalar('LR8', cr.neg_cap, cr.qf_in0, 'MAX') }} {{ save('identity', cr.qf_out0, slot, ds='.H') }} ;;
    LD.MULT R0 {{ slot }} {{ cr.s0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.H {{ cr.qf_out0 }}.L ; ACC.SUB.FIRST {{ save('relu', cr.qf_out0, slot, ds='.H') }} ;;
{% endfor %}
    LD.MULT R0 LR5 {{ cr.s0 }} ;;
    MULT.VE LR0 {{ cr.two }} 0 LR0 {{ cr.full }}.H {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR14 {{ cr.s0 }} ;;
    MULT.VE LR0 {{ cr.two }} 0 LR0 {{ cr.full }}.H {{ cr.qf_out0 }}.L ; ACC.SUB {{ save('identity', cr.qf_out0, 'LR1', cr.out0, '.H') }} ;;
    INC LR1 1 ;;
    BLT.S LR3 LR12 row ;;
    BLT.S LR1 LR10 channel ;;
    SET LR11 LR2 ; BGE.S LR1 LR15 finish ;;
    ADD LR10 LR10 LR9 ; BEQ LR0 LR0 batch ;;
finish:
    HALT ;;
