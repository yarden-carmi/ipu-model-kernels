{% set ix = (in0_d3 + 127) // 128 %}
{% set width = out0_d3 %}
{% set full = [out0_d2, 128 // width]|min %}
{% set pack = full if out0_d2 % full == 0 else 1 %}
{% set tiles = out0_d2 // pack %}
{% set taps = kh * kw %}
{% set gc = cin // groups %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% macro adjust(reg, n) %}
{% for off in range(0, n|abs, 255) %}
{{ 'INC' if n > 0 else 'DEC' }} {{ reg }} {{ [255, n|abs - off]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro bound(reg, n) %}
SET {{ reg }} CR0 ;;
{{ adjust(reg, n) }}
{% endmacro %}
{% macro zero_rows(label, count) %}
{{ bound('LR13', count - 1) }}
SET LR12 CR0 ;;
{{ label }}:
MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ; INC LR12 1 ; BLT.S LR12 LR13 {{ label }} ;;
{% endmacro %}
{% macro shift_tap(kx) %}
SET LR8 LR1 ;;
{{ adjust('LR8', kx - padding) }}
{% if stride == 1 %}
MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
{% else %}
MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
{% if width > 64 %}
INC LR8 128 ;;
MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ;;
{% endif %}
{% endif %}
ACTIVATE.QUANTIZE identity {{ cr.ds_width }}.L {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;;
{% endmacro %}
SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
DEC LR4 1 ; DEC LR5 1 ; SET LR6 CR0 ;;
{{ bound('LR1', 128) }}
{{ bound('LR2', 256) }}
{{ bound('LR3', 384) }}
{{ bound('LR9', 2) }}
{{ bound('LR10', in0_d2 - 1) }}
{{ bound('LR11', cin - 1) }}
{{ zero_rows('sentinel', 1) }}
LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR2 ;;
LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR3 ;;
shift_channel:
{{ zero_rows('top', padding * kw) }}
SET LR7 CR0 ;;
shift_y:
LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
{% if ix == 2 %}
LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;
{% endif %}
{% if in0_d3 % 128 %}
{% set tail = 'LR2' if ix == 2 else 'LR1' %}
MULT.RC.VE {{ tail }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
ACTIVATE.QUANTIZE identity {{ cr.ds_input }}.L {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;;
LD.MULT.CYCLIC LR5 {{ cr.shifted }} {{ tail }} ;;
DEC LR5 1 ;;
{% endif %}
{% for kx in range(kw) %}
{{ shift_tap(kx) }}
{% endfor %}
INC LR7 1 ; BLT.S LR7 LR10 shift_y ;;
{{ zero_rows('bottom', padding * kw) }}
INC LR6 1 ; BLT.S LR6 LR11 shift_channel ;;
{% macro accumulate_tap(tap) %}
MULT.RC.VE LR2 LR8 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR8 1 ;;
MULT.RC.VE LR2 LR9 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR9 1 ;
{% if tap + 1 < taps %}LD.MULT.CYCLIC LR14 {{ cr.shifted }} LR1 ; INC LR14 1 ;{% endif %} ;;
{% endmacro %}
LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;
SET LR13 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
DEC LR13 1 ; DEC LR5 1 ;;
{% for i in range(5) %}
LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
{{ bound('LR10', -1) }}
output_group:
SET LR15 CR0 ; SET LR3 LR6 ;;
{{ adjust('LR3', (tiles - 1) * stride * pack * kw) }}
output_channel:
SET LR4 LR6 ;;
output_y:
SET LR11 LR10 ; SET LR12 LR4 ; SET LR2 LR1 ;;
LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ;;
MULT.EE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
output_segment:
SET LR11 LR10 ; SET LR13 LR12 ;;
INC LR11 3 ;;
{% if gc > 1 %}
SET LR7 LR11 ;;
{{ adjust('LR7', 3 * gc) }}
{% endif %}
input_channel:
LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR8 CR0 ; SET LR9 LR1 ;;
LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR14 LR13 ; DEC LR8 1 ;;
LD.MULT.CYCLIC LR14 {{ cr.shifted }} LR1 ; INC LR14 1 ; DEC LR9 1 ;;
{% for tap in range(taps) %}
{{ accumulate_tap(tap) }}
{% endfor %}
LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR14 LR13 ; SET LR8 CR0 ;;
DEC LR8 1 ; LD.MULT.CYCLIC LR14 {{ cr.shifted }} LR1 ; INC LR14 1 ;;
{% for tap in range(taps) %}
MULT.RC.VE LR2 LR8 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR8 1 ; {% if not loop.last %}LD.MULT.CYCLIC LR14 {{ cr.shifted }} LR1 ; INC LR14 1 ;{% endif %} ;;
{% endfor %}
{% if gc > 1 %}
ADD LR13 LR13 {{ cr.plane }} ; BLT.S LR11 LR7 input_channel ;;
{% else %}
ADD LR13 LR13 {{ cr.plane }} ;;
{% endif %}
{% if pack > 1 %}
{{ bound('LR7', 128 - (pack - 1) * width) }}
DEC LR2 {{ width }} ; INC LR12 {{ stride * kw }} ; BNE LR2 LR7 output_segment ;;
{% endif %}
ACTIVATE.QUANTIZE generic {{ cr.ds_pack }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR4 {{ stride * pack * kw }} ; BLT.S LR4 LR3 output_y ;;
SET LR10 LR11 ;;
{{ bound('LR12', cout // groups - 1) }}
INC LR15 1 ; BLT.S LR15 LR12 output_channel ;;
SET LR6 LR13 ;;
{{ adjust('LR6', -(out0_d2 - 1) * stride * kw) }}
BLT.S LR10 {{ cr.weights_end }} output_group ;;
HALT ;;
