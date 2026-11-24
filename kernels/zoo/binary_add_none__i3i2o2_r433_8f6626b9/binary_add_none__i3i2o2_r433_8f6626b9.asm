{% macro add_store(ds) %}
    LD.MULT R0 LR4 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    SET LR10 CR0 ;;
    INC LR10 128 ;;

// View coordinate (phase, position, channel) reads spatial position
// position * phases + phase in the source channel's packed rows.
phase:
    SET LR1 LR3 ; SET LR2 CR0 ; SET LR8 {{ cr.out0_d1 }} ;;
position:
    SET LR5 {{ cr.out0_d2 }} ; SET LR6 LR2 ;;
chunk:
    SET LR7 CR0 ; SET LR9 LR10 ; BLT.S LR10 LR5 gather ;;
    SET LR9 LR5 ;;
gather:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR7 {{ cr.scalar }}.L ; ADD LR6 LR6 {{ cr.channel_stride }} ;;
    INC LR7 1 ;;
    BLT.S LR7 LR9 gather ;;
    BLE.S LR5 LR10 tail ;;
    {{ add_store(cr.full ~ '.L') }}
    DEC LR5 128 ; B chunk ;;
tail:
    {{ add_store(cr.tail ~ '.L') }}
    DEC LR8 1 ;;
    BEQ LR8 CR0 next_phase ;;
    ADD LR1 LR1 {{ cr.out0_d0 }} ;;
    BLT.S LR1 {{ cr.spatial_lanes }} position ;;
    SUB LR1 LR1 {{ cr.spatial_lanes }} ; INC LR2 1 ; B position ;;
next_phase:
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.out0_d0 }} phase ;;
    HALT ;;
