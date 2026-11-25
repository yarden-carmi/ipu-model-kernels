{% set chunks = (in0_d1 + 127) // 128 %}
{% set gc = cin // groups %}
{% set cap = [out0_d2, 128 // out0_d3]|min %}
{% set pack = cap if out0_d2 % cap == 0 else 1 %}
{% set tiles = out0_d2 // pack %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% macro adjust(reg, n) %}
 {% for k in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ reg }} {{ [255, n|abs-k]|min }} ;;
 {% endfor %}
{% endmacro %}
{% macro number(reg, n) %}
 SET {{ reg }} CR0 ;;
 {{ adjust(reg, n) }}
{% endmacro %}
{% macro clear() %}
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST
{%- endmacro %}
{% macro vertical_pad(label) %}
 {% if padding %}
 {{ number('LR10', padding * kw - 1) }}
 {{ label }}:
 {{ clear() }} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.taps }} LR9 ; INC LR9 1 ; DEC LR10 1 ; BLT.S CR0 LR10 {{ label }} ;;
 {% endif %}
{% endmacro %}
{% macro gather(label, first, end, k) %}
 {{ clear() }} ;;
 {% if first < end %}
 SET LR8 LR7 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 {{ adjust('LR8', (first * stride + k - padding) * chunks) }}
 {% if first %}ADDBI LRD4 {{ first }} ;;{% endif %}
 LD.MULT R0 LR8 {{ cr.in0 }} ;;
 {% if end - first > 1 %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD2 LRD4 7 ; LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR8 {{ stride * chunks }} ;;
 {% if end - first > 2 %}
 {{ number('LR10', end - first - 3) }}
 {{ label }}:
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD2 LRD4 7 ; LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR8 {{ stride * chunks }} ; ADDBI LRD4 1 ; DEC LR10 1 ; BLT.S CR0 LR10 {{ label }} ;;
 {% endif %}
 ADDBI LRD4 1 ;;
 {% endif %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD2 LRD4 7 ;;
 {% endif %}
{% endmacro %}
{% macro save_scanline() %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.taps }} LR9 ; ADD LR8 LR9 {{ cr.residual_offset }} ;;
 LD.MULT R0 LR9 {{ cr.taps }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.taps }} LR8 ; INC LR9 1 ;;
{% endmacro %}
{% macro packed_gather(label, first, end, ky, kx) %}
 {{ clear() }} ; SET LR4 CR0 ; SET LR5 CR0 ; SET LR7 LR6 ;;
 {% if first < end %}
 {{ adjust('LR7', ky * in0_d3 * chunks) }}
 {{ number('LR11', pack - 1) }}
 {% if first %}ADDBI LRD4 {{ first }} ;;{% endif %}
 {{ label }}_y:
 BLT.S LR7 CR0 {{ label }}_skip ;;
 BLT.S LR7 {{ cr.input_end }} {{ label }}_valid ;;
 {{ label }}_skip:
 ADDBI LRD4 {{ out0_d3 }} ; B {{ label }}_next ;;
 {{ label }}_valid:
 ADD LR8 LR7 LR1 ;;
 {{ adjust('LR8', (first * stride + kx - padding) * chunks) }}
 LD.MULT R0 LR8 {{ cr.in0 }} ;;
 {% if end - first > 1 %}
 {{ number('LR10', end - first - 2) }}
 {{ label }}_x:
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD2 LRD4 7 ; LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR8 {{ stride * chunks }} ;;
 ADDBI LRD4 1 ; DEC LR10 1 ; BLT.S CR0 LR10 {{ label }}_x ;;
 {% endif %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD2 LRD4 7 ;;
 ADDBI LRD4 {{ out0_d3 - (end - first - 1) }} ;;
 {{ label }}_next:
 ADD LR7 LR7 {{ cr.row_step }} ; DEC LR11 1 ; BLT.S CR0 LR11 {{ label }}_y ;;
 {% endif %}
 {{ save_scanline() }}
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR6 CR0 ; SET LR14 CR0 ;;
 {{ number('LR13', cin - 1) }}
 {{ number('LR15', 127) }}

 {# Transpose sampled channels into scanlines; save a second row for rounding residuals. #}
 {% if pack > 1 %}
 SET LR9 CR0 ;;
 {% endif %}
 stage_channel:
 {% if pack > 1 %}
 {{ number('LR6', -padding * in0_d3 * chunks) }}
 {{ number('LR12', tiles - 1) }}
 stage_tile:
 {% for t in range(kh * kw) %}
 {% set k = t % kw %}
 {% set first = [0, (padding - k + stride - 1) // stride]|max %}
 {% set end = [out0_d3, (in0_d3 + padding - k + stride - 1) // stride]|min %}
 {{ packed_gather('packed_' ~ t, first, end, t // kw, k) }}
 {% endfor %}
 {{ number('LR11', pack - 1) }}
 stage_next_tile:
 ADD LR6 LR6 {{ cr.row_step }} ; DEC LR11 1 ; BLT.S CR0 LR11 stage_next_tile ;;
 DEC LR12 1 ; BLT.S CR0 LR12 stage_tile ;;
 DEC LR13 1 ; BEQ LR13 CR0 stage_done ;;
 {% else %}
 SET LR9 LR6 ; SET LR7 LR1 ;;
 DEC LR9 1 ;;
 {{ vertical_pad('top_pad') }}
 {% if padding %}
 SET LR11 LR9 ; ADD LR9 LR9 {{ cr.residual_offset }} ;;
 DEC LR9 {{ padding * kw }} ;;
 {{ vertical_pad('top_residual') }}
 SET LR9 LR11 ;;
 {% endif %}
 INC LR9 1 ;;
 {{ number('LR12', in0_d2 - 1) }}
 stage_y:
 {% for k in range(kw) %}
 {% set first = [0, (padding - k + stride - 1) // stride]|max %}
 {% set end = [out0_d3, (in0_d3 + padding - k + stride - 1) // stride]|min %}
 {{ gather('gather_' ~ k, first, end, k) }}
  {{ save_scanline() }}
 {% endfor %}
 ADD LR7 LR7 {{ cr.row_step }} ; DEC LR12 1 ; BLT.S CR0 LR12 stage_y ;;
 DEC LR9 1 ;;
 {{ vertical_pad('bottom_pad') }}
 {% if padding %}
 ADD LR9 LR9 {{ cr.residual_offset }} ;;
 DEC LR9 {{ padding * kw }} ;;
 {{ vertical_pad('bottom_residual') }}
 {% endif %}
 ADD LR6 LR6 {{ cr.plane }} ; DEC LR13 1 ; BEQ LR13 CR0 stage_done ;;
 {% endif %}
 BEQ LR14 LR15 next_chunk ;;
 ADDBI LRD2 1 ; INC LR14 1 ; B stage_channel ;;
 next_chunk:
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR14 CR0 ;;
 INC LR1 1 ; B stage_channel ;;
 stage_done:

 {# A zero cyclic slot supplies the part of a rotated scanline outside its range. #}
 ADD LR8 LR0 {{ cr.residual_offset }} ;;
 ADD LR8 LR8 {{ cr.residual_offset }} ; INC LR15 1 ;;
 {{ clear() }} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.taps }} LR8 ;;
 INC LR15 255 ;;
 INC LR15 1 ;;
 LD.MULT.CYCLIC LR8 {{ cr.taps }} LR15 ;;
 SET LR4 CR0 ; SET LR6 CR0 ;;
 {{ number('LR5', -1) }}
 {{ number('LR13', groups - 1) }}
 group_loop:
 {{ number('LR12', cout // groups - 1) }}
 channel_loop:
 SET LR7 LR6 ;;
 {{ number('LR11', tiles - 1) }}
 tile_loop:
 SET LR8 LR4 ; SET LR15 CR0 ;;
 {% for b in range(3) %}
 LD.MULT R0 LR8 {{ cr.weights }}{% if b > 0 %} ; INC LR8 1 ; MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD{% if b == 1 %}.FIRST{% endif %}{% endif %} ;;
 {% endfor %}
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
 scanline:
 SET LR8 LR4 ; SET LR9 LR7 ;;
 INC LR8 2 ;;
 {{ number('LR10', gc - 1) }}
 input_channel:
 {% for part in range(3) %}
 SET LR14 LR9 ; SET LR2 CR0 ; ADD LR3 LR9 {{ cr.residual_offset }} ;;
 LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ; DEC LR2 1 ; DEC LR3 1 ;;
 LD.MULT.CYCLIC LR14 {{ cr.taps }} LR0 ;;
 {% for t in range(kh * kw) %}
 MULT.RC.VE LR15 LR2 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR2 1 ; LD.MULT.CYCLIC LR3 {{ cr.taps }} LR0 ; INC LR3 1 ;;
 MULT.RC.VE LR15 LR2 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
 {% if not loop.last %}LD.MULT.CYCLIC LR14 {{ cr.taps }} LR0 ; INC LR14 1 ;{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {% if gc > 1 %}
 ADD LR9 LR9 {{ cr.plane }} ; DEC LR10 1 ; BLT.S CR0 LR10 input_channel ;;
 {% endif %}
 INC LR7 {{ kh * kw if pack > 1 else stride * kw }} ;;
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; DEC LR11 1 ; BLT.S CR0 LR11 tile_loop ;;
 SET LR4 LR8 ;;
 INC LR4 1 ; DEC LR12 1 ; BLT.S CR0 LR12 channel_loop ;;
 ADD LR6 LR6 {{ cr.group_plane }} ; DEC LR13 1 ; BLT.S CR0 LR13 group_loop ;;
 HALT ;;
