{% macro store_row(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.store_ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
{% endmacro %}
    SET LR1 {{ cr.lanes_start }} ;;
    SET LR14 {{ cr.phases }} ;;
channel:
    SET LR13 {{ cr.loop_bounds }}.H ;;
phase:
    SET LR6 {{ cr.sites_y }} ;;
    SET LR7 LR4 ;;
    SET LR11 LR12 ;;
site_y:
    SET LR8 LR11 ;;
    SET LR9 {{ cr.loop_bounds }}.L ;;
chunk:
    SET LR3 {{ cr.lanes_start }} ;;
site_x:
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.store_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 4 ; DEC LR9 1 ;;
    ADD LR7 LR7 {{ cr.input_stride }} ; BEQ LR9 CR0 last_chunk ;;
    ADD LR3 LR3 {{ cr.lanes_step }} ;;
    BNE LR3 {{ cr.lanes_end }} site_x ;;
{{ store_row("L") }}
    INC LR8 1 ; BEQ LR0 CR0 chunk ;;
last_chunk:
{{ store_row("H") }}
    ADD LR11 LR11 {{ cr.y_stride }} ; DEC LR6 1 ;;
    BNE LR6 CR0 site_y ;;
    ADD LR1 LR1 {{ cr.lanes_step }} ; DEC LR14 1 ; DEC LR13 1 ;;
    BEQ LR14 CR0 done ;;
    BNE LR1 {{ cr.lanes_end }} next_phase ;;
    SET LR1 {{ cr.lanes_start }} ; INC LR4 1 ;;
next_phase:
    ADD LR12 LR12 {{ cr.phase_stride }} ; BNE LR13 CR0 phase ;;
    INC LR15 1 ;;
    SET LR12 LR15 ; BEQ LR0 CR0 channel ;;
done:
    HALT ;;
