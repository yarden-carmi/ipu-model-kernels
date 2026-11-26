// Gather in0 at flat index i + d0*j + d0*d1*k, in output order.
// LR5:LR6 is the row/lane for k=0; LR8:LR9 is the current source.
{% macro advance(row, lane, row_step, lane_step, label) %}
    {% if row_step %}ADD {{ row }} {{ row }} {{ row_step }} ;{% endif %}
    ADD {{ lane }} {{ lane }} {{ lane_step }} ;;
    BLT.S {{ lane }} LR14 {{ label }} ;;
    INC {{ row }} 1 ; DEC {{ lane }} 128 ; B {{ label }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR13 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; INC LR14 128 ;;
new_row:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR12 CR0 ;;
gather:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    INC LR10 1 ; INC LR12 1 ; ADDBI LRD2 1 ;;
    BEQ LR10 {{ cr.out0_d2 }} next_line ;;
{% if (out0_d0 * out0_d1) % 128 == 0 %}
    ADD LR8 LR8 {{ cr.step_row }} ; B gathered ;;
{% else %}
    {{ advance('LR8', 'LR9', cr.step_row, cr.step_lane, 'gathered') }}
{% endif %}
next_line:
    SET LR10 CR0 ; INC LR11 1 ;;
    BEQ LR11 {{ cr.out0_d1 }} next_plane ;;
    {{ advance('LR5', 'LR6', none, cr.out0_d0, 'line_start') }}
next_plane:
    INC LR7 1 ; SET LR11 CR0 ;;
    SET LR5 CR0 ; SET LR6 LR7 ;;
line_start:
    SET LR8 LR5 ; SET LR9 LR6 ;;
gathered:
    BLT.S LR12 LR14 gather ;;
    LD.MULT R0 LR13 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ; BNE LR7 {{ cr.out0_d0 }} new_row ;;
    HALT ;;
