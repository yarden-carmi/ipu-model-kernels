{% set pack = 128 // out0_d0 %}
// LR2: output row, LR3: input column block, LR4: input lane.
column:
    SET LR5 CR0 ; SET LR6 LR3 ;;
block:
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR7 CR0 ;;
    SET LR10 {{ cr.last_count }} ; SET LR11 LR5 ;;
    INC LR11 1 ;;
    BEQ LR11 {{ cr.blocks }} last_block ;;
    SET LR10 CR0 ;;
    INC LR10 {{ pack }} ;;
last_block:
    SET LR12 LR6 ;;
gather:
{% for batch in range(out0_d0) %}
    LD.MULT R0 LR12 {{ cr.in0 }} {% if not loop.first %}; ADDBI LRD8 1{% endif %} ;;
    MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD8 7 ; ADD LR12 LR12 {{ cr.batch_stride }} ;;
{% endfor %}
    ADDBI LRD8 1 ; ADD LR6 LR6 {{ cr.input_stride }} ; INC LR7 1 ;;
    SET LR12 LR6 ; BLT.S LR7 LR10 gather ;;
    LD.MULT R0 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    BEQ LR11 {{ cr.blocks }} store_tail ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR5 1 ; B block ;;
store_tail:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR4 1 ;;
    SET LR11 CR0 ;;
    INC LR11 128 ;;
    BLT.S LR4 LR11 no_wrap ;;
    SET LR4 CR0 ; INC LR3 1 ;;
no_wrap:
    INC LR13 1 ;;
    BLT.S LR13 {{ cr.out0_d2 }} column ;;
    HALT ;;
