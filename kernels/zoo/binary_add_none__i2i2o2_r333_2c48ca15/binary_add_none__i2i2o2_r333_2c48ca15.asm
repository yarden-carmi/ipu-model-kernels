// Gather the strided view one element at a time into the accumulator.
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR10 CR0 ;;
    SET LR11 CR0 ; SET LR13 CR0 ;;
outer:
    SET LR4 LR8 ; SET LR5 LR9 ; SET LR12 CR0 ;;
block:
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR14 CR0 ;;
gather:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.EE LR4 CR1 0 LR10 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    INC LR5 {{ (out0_d1 // 128) }} ; INC LR4 {{ (out0_d1 % 128) }} ; INC LR14 1 ;;
    BLT.S LR4 {{ cr.c128 }} no_carry ;;
    DEC LR4 128 ; INC LR5 1 ;;
no_carry:
    ADDBI LRD2 1 ; BLT.S LR14 {{ cr.c128 }} gather ;;
    LD.MULT R0 LR11 {{ cr.in1 }} ;;
    MULT.VE LR10 CR1 0 LR10 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ;;
    INC LR11 1 ; INC LR12 1 ;;
    BLT.S LR12 {{ cr.blocks }} block ;;
    INC LR8 1 ;;
    BLT.S LR8 {{ cr.c128 }} start_ok ;;
    SET LR8 CR0 ; INC LR9 1 ;;
start_ok:
    INC LR13 1 ;;
    BLT.S LR13 {{ cr.out0_d1 }} outer ;;
{% if out0_d1 % 256 %}
    MULT.VE LR10 CR0 0 LR10 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
pad:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.empty }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ;;
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.padded_rows }} pad ;;
{% endif %}
    HALT ;;
