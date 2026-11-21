// in0's view offset is ((column * height + row) * channels + channel).
// Split that offset into a physical row (LR1) and a storage lane (LR2).
{% macro wrap(label) %}
{{ label }}:
    BLT.S LR1 {{ cr.plane }} {{ label }}_done ;;
    SUB LR1 LR1 {{ cr.plane }} ; INC LR2 1 ; B {{ label }} ;;
{{ label }}_done:
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    SET LR6 CR0 ; SET LR13 {{ cr.out0_d1 }} ;;
row:
    SET LR1 LR4 ; SET LR2 CR0 ; SET LR7 {{ cr.out0_d2 }} ;;
    {{ wrap('row_wrap') }}
    SET LR15 CR0 ; INC LR14 0 ;;
    INC LR15 128 ;;
chunk:
    // Cache one row per in1 channel in the four cyclic slots.
    SET LR11 CR0 ; SET LR12 LR6 ; SET LR10 CR0 ;;
load_channel:
    LD.MULT.CYCLIC LR12 {{ cr.in1 }} LR11 ;;
    ADD LR12 LR12 {{ cr.channel_rows }} ; INC LR11 128 ; INC LR10 1 ;;
    BLT.S LR10 {{ cr.out0_d0 }} load_channel ;;
    SET LR8 CR0 ; INC LR6 1 ;;
pixel:
    SET LR10 CR0 ; SET LR9 LR8 ;;
channel:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.EE LR2 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR10 {{ cr.one }}.L ; INC LR1 1 ;;
    MULT.RC.VE LR9 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR10 {{ cr.one }}.L ;;
    INC LR10 1 ; INC LR9 128 ;;
    {{ wrap('channel_wrap') }}
    BLT.S LR10 {{ cr.out0_d0 }} channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; DEC LR7 1 ; INC LR8 1 ;;
    BEQ LR7 CR0 next_row ;;
    ADD LR1 LR1 {{ cr.gap }} ;;
    {{ wrap('pixel_wrap') }}
    BLT.S LR8 LR15 pixel ;;
    B chunk ;;
next_row:
    ADD LR4 LR4 {{ cr.out0_d0 }} ; DEC LR13 1 ;;
    BNE LR13 CR0 row ;;
    HALT ;;
