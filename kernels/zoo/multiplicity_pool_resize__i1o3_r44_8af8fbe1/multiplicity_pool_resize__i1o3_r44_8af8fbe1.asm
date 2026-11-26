{% macro load(ptr) %}LD.MULT.CYCLIC {{ ptr }} {{ cr.in0 }} LR0{% endmacro %}
{% macro mul(idx, weight) %}MULT.RC.VE {{ idx }} {{ weight }} 0 LR0 {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L{% endmacro %}
{% macro output(center, side, x, xy) %}
{{ load('LR3') }} ;;
{{ mul(center, cr.center) }} ; ACC.ADD.FIRST ; {{ load(x) }} ;;
{{ mul(side, cr.side) }} ; ACC.ADD ; {{ load('LR4') }} ;;
{{ mul(center, cr.side) }} ; ACC.ADD ; {{ load(xy) }} ;;
{{ mul(side, cr.corner) }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR8 ;;
INC LR8 1 ;;
{% endmacro %}
{% macro row(phase) %}
ADD LR2 LR1 CR0 ;;
BEQ LR10 {{ 'CR0' if phase == 'even' else cr.last_y }} y_clamped_{{ phase }} ;;
{{ 'SUB' if phase == 'even' else 'ADD' }} LR2 LR1 {{ cr.w }} ;;
y_clamped_{{ phase }}:
ADD LR3 LR1 CR0 ; ADD LR4 LR2 CR0 ; SET LR9 CR0 ;;
x_loop_{{ phase }}:
BEQ LR9 CR0 left_clamped_{{ phase }} ;;
ADD LR5 LR3 CR0 ; ADD LR6 LR4 CR0 ;;
DEC LR5 1 ; DEC LR6 1 ;;
{{ output('LR0', 'LR7', 'LR5', 'LR6') }}
BEQ CR0 CR0 left_done_{{ phase }} ;;
left_clamped_{{ phase }}:
{{ output('LR0', 'LR0', 'LR3', 'LR4') }}
left_done_{{ phase }}:
{{ output('LR0', 'LR7', 'LR3', 'LR4') }}
{{ output('LR7', 'LR0', 'LR3', 'LR4') }}
BEQ LR9 {{ cr.last_x }} right_clamped_{{ phase }} ;;
ADD LR5 LR3 CR0 ; ADD LR6 LR4 CR0 ;;
INC LR5 1 ; INC LR6 1 ;;
{{ output('LR7', 'LR0', 'LR5', 'LR6') }}
BEQ CR0 CR0 right_done_{{ phase }} ;;
right_clamped_{{ phase }}:
{{ output('LR7', 'LR7', 'LR3', 'LR4') }}
right_done_{{ phase }}:
INC LR3 1 ; INC LR4 1 ; INC LR9 1 ; BLT.S LR9 {{ cr.last_x }} x_loop_{{ phase }} ;;
{% endmacro %}
INC LR7 {{ in0_d1 }} ;;
batch_loop:
SET LR10 CR0 ;;
y_loop:
{{ row('even') }}
{{ row('odd') }}
ADD LR1 LR1 {{ cr.w }} ; INC LR10 1 ; BLT.S LR10 {{ cr.last_y }} y_loop ;;
INC LR11 1 ; BLT.S LR11 {{ cr.last_batch }} batch_loop ;;

SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
SET LR8 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
SET LR12 CR0 ; SET LR13 CR0 ;;
INC LR11 {{ out0_d3 - 1 }} ; INC LR12 {{ out0_d2 - 1 }} ; INC LR13 {{ out0_d1 - 1 }} ;;
channel_loop:
SET LR5 CR0 ; SET LR7 CR0 ;;
transpose_row:
SET LR2 CR0 ; SET LR3 CR0 ; SET LR6 CR0 ;;
transpose_x:
LD.MULT R0 LR7 {{ cr.tmp }} ;;
MULT.EE LR4 CR1 0 LR10 {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR7 1 ;;
ADDBI LRD2 1 ; INC LR6 1 ; BLT.S LR6 LR11 transpose_x ;;
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
INC LR8 1 ; INC LR5 1 ; BLT.S LR5 LR12 transpose_row ;;
INC LR4 1 ; BLT.S LR4 LR13 channel_loop ;;
HALT ;;
