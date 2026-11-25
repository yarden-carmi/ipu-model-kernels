// Unpadded view offset is x * (B * Y) + y * B + b.
// Keep it as a padded physical row base and an unpadded column.
{% macro advance(row, col, step, distance, tag) %}
    {% if distance // in0_d2 %}ADD {{ row }} {{ row }} {{ step }}.H ;{% endif %}
    {% if distance % in0_d2 %}
    ADD {{ col }} {{ col }} {{ step }}.L ;;
    BLT.S {{ col }} {{ cr.limits }}.L {{ tag }} ;;
    SUB {{ col }} {{ col }} {{ cr.limits }}.L ; ADD {{ row }} {{ row }} {{ cr.limits }}.H ;;
{{ tag }}:
    {% elif distance // in0_d2 %};;{% endif %}
{% endmacro %}

    SET LR15 {{ cr.rows_ds }}.L ;;
    INC LR14 128 ;;
y_loop:
    SET LR4 LR12 ; SET LR5 LR13 ; SET LR11 {{ cr.columns_lanes }}.L ;;
x_loop:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR10 {{ cr.columns_lanes }}.H ;;
    SET LR2 CR0 ; SET LR3 CR0 ;;
lane_loop:
    SET LR8 LR6 ; SET LR9 LR7 ; BLT.S LR7 LR14 load_lane ;;
wrap_physical:
    INC LR8 1 ; DEC LR9 128 ;;
    BGE.S LR9 LR14 wrap_physical ;;
load_lane:
    LD.MULT R0 LR8 {{ cr.in0 }} ; DEC LR10 1 ; INC LR7 1 ;;
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD2 0 ; BEQ LR10 CR0 add_row ;;
    ADDBI LRD2 1 ; BLT.S LR7 {{ cr.limits }}.L lane_loop ;;
    SET LR7 CR0 ; ADD LR6 LR6 {{ cr.limits }}.H ; B lane_loop ;;
add_row:
    LD.MULT R0 LR1 {{ cr.in1 }} ; DEC LR11 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.rows_ds }}.H {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.rows_ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; BEQ LR11 CR0 next_y ;;
    {{ advance('LR4', 'LR5', cr.x_step, out0_d0 * out0_d1, 'next_x') }}
    B x_loop ;;
next_y:
    DEC LR15 1 ;;
    BEQ LR15 CR0 finish ;;
    {{ advance('LR12', 'LR13', cr.y_step, out0_d0, 'y_ready') }}
    B y_loop ;;
finish:
    HALT ;;
