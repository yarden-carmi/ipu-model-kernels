{# Keep the full input chunk resident while streaming its weight rows. #}
{% macro channel(i, count) %}
{% set cur = 'LR15' if i % 2 == 0 else 'LR12' %}
{% set nxt = 'LR12' if i % 2 == 0 else 'LR15' %}
 {% if i + 1 < count %}LD.MULT.CYCLIC LR4 {{ cr.weights }} {{ nxt }} ; {% endif %}MULT.RC.VE {{ cur }} LR11 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 {% if i > 0 %}; INC LR11 1{% endif %} ;;
{% endmacro %}
{% macro chunk(count) %}
 LD.MULT R0 LR9 {{ cr.in0 }} ; SET LR11 CR0 ;;
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; INC LR9 1 ;;
{% for tile in range((count + 31) // 32) %}
{% for lane in range([32, count - tile * 32]|min) %}
 {{ channel(tile * 32 + lane, count) }}
{% endfor %}
{% endfor %}
{% endmacro %}
{% set fast = kh == 3 and kw == 3 and padding == 1 and stride == 1 and cin <= 64 %}
{% set dot = cin >= 96 and cout <= 64 %}
{# Wide reductions: keep the input chunk resident and stream one dot-product row per output. #}
{% macro dot_tap() %}
{% for i in range(chunks) %}
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR15 ; SET LR11 CR0 ;;
 LD.MULT R0 LR4 {{ cr.weights }} ; INC LR9 1 ; DEC LR11 1 ;;
{% if cout > 1 %}
 dot_loop_{{ i }}:
 MULT.RC.VV LR15 R0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.full }}.L ; INC LR11 1 ; LD.MULT R0 LR4 {{ cr.weights }} ; INC LR4 1 ; BLT.S LR11 LR10 dot_loop_{{ i }} ;;
{% endif %}
 MULT.RC.VV LR15 R0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.full }}.L ; INC LR11 1 ; INC LR4 1 ;;
{% endfor %}
{% endmacro %}
{% macro fast_tap() %}
 LD.MULT R0 LR9 {{ cr.in0 }} ; SET LR11 CR0 ;;
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; INC LR9 1 ;;
{% for tile in range((cin + 31) // 32) %}
{% for lane in range([32, cin - tile * 32]|min) %}
 {{ channel(tile * 32 + lane, cin) }}
{% endfor %}
{% endfor %}
{% endmacro %}
{% macro pair_tap(tag, diff=0) %}
 SET LR10 CR0 ;;
 DEC LR10 {{ chunks - 1 }} ;;
{% if diff %}
 INC LR9 2 ;;
{% endif %}
 pair_chunk_{{ tag }}:
 LD.MULT R0 LR9 {{ cr.delta_or_scratch if diff else cr.in0 }} ; SET LR11 CR0 ;;
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; SET LR14 CR0 ; INC LR9 1 ;;
 INC LR14 110 ; DEC LR11 1 ;;
 pair_channels_{{ tag }}:
{% for i in range(16) %}
 {{ pair_channel(i, true, 'BLT.S LR11 LR14 pair_channels_' ~ tag if i == 15 else '') }}
{% endfor %}
{% for i in range(16) %}
 {{ pair_channel(i, i != 15, 'BLT.S LR10 CR0 pair_chunk_' ~ tag if i == 15 else '') }}
{% endfor %}
{% if diff %}
 DEC LR9 2 ;;
{% endif %}
{% endmacro %}
{% macro pair_channel(i, more, branch) %}
{% set cur = 'LR15' if i % 2 == 0 else 'LR12' %}
{% set nxt = 'LR12' if i % 2 == 0 else 'LR15' %}
 MULT.RC.VE {{ cur }} LR11 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR11 1 ; INC LR4 1{% if more %} ; LD.MULT.CYCLIC LR4 {{ cr.weights }} {{ nxt }}{% endif %}{% if not more %} ; INC LR10 1{% endif %}{% if branch %} ; {{ branch }}{% endif %} ;;
{% endmacro %}
{% macro shift(r, n) %}
{% for tile in range(0, n | abs, 8160) %}
{% for k in range(tile, [tile + 8160, n | abs] | min, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255, (n | abs) - k] | min }} ;;
{% endfor %}
{% endfor %}
{% endmacro %}
{% macro phase_start(tag, resumed=false) %}
 SET LR4 LR6 ; SET LR5 LR0 ; SET LR8 LR1 ;;
{% if resumed %}
 LD.MULT.CYCLIC LR15 {{ cr.delta_or_scratch }} LR15 ; INC LR4 1 ; SET LR14 CR0 ;;
 INC LR14 1 ; LD.MULT R0 LR14 {{ cr.delta_or_scratch }} ;;
 MULT.RC.VE LR15 CR1 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR15 CR1 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; BGE.S LR5 CR0 pair_y_{{ tag }} ;;
{% else %}
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 INC LR4 1 ;;
 MULT.RC.VE LR15 {{ 'CR1' if bias or resumed else 'CR0' }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; BGE.S LR5 CR0 pair_y_{{ tag }} ;;
{% endif %}
{% for i in range(4) %}
 ADD LR4 LR4 {{ cr.cin_or_panel }} ;;
{% endfor %}
 INC LR5 1 ; ADD LR8 LR8 {{ cr.input_pitch }} ;;
 pair_y_{{ tag }}:
{% endmacro %}
{% macro phase_end(tag, next='') %}
 INC LR5 1 ; ADD LR8 LR8 {{ cr.input_pitch }} ; BGE.S LR5 LR7 {{ next or 'pair_end_' ~ tag }} ;;
 BLT.S LR5 {{ cr.in0_d2 }} pair_y_{{ tag }} ;;
{% if not next %}
 pair_end_{{ tag }}:
{% endif %}
{% endmacro %}
{% macro prep(tag, start, anchor) %}
 SET LR9 LR8 ; SET LR14 LR8 ; SET LR10 CR0 ;;
 INC LR9 {{ start }} ; INC LR14 {{ anchor }} ; DEC LR10 {{ chunks - 1 }} ;;
 prep_{{ tag }}:
 LD.MULT R0 LR9 {{ cr.in0 }} ;;
 LD.MULT R1 LR14 {{ cr.in0 }} ; SET LR11 LR9 ; INC LR9 1 ;;
 MULT.VE LR15 CR1 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR14 1 ; INC LR11 2 ;;
 MULT.VE LR12 CR1 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.delta_or_scratch }} LR11 ; INC LR10 1 ; BLT.S LR10 CR0 prep_{{ tag }} ;;
{% endmacro %}
{% if pair %}
{# Adjacent stride-two windows share v on their outer taps:
   a*u+b*v = a*(u-v)+(a+b)*v; a*v+b*w = b*(w-v)+(a+b)*v.
   Compute the boundary pair directly. Store the shared accumulator as a
   rounded row plus its residual so cancellation does not discard precision. #}
 INC LR12 128 ; DEC LR0 1 ;;
 pair_oy:
 SET LR2 CR0 ; SET LR7 LR0 ;;
 DEC LR2 1 ; INC LR7 2 ;;
 pair_ox:
 SET LR6 CR0 ; SET LR3 CR0 ; SET LR14 CR0 ;;
 INC LR14 3 ;;
 BGE.S LR2 LR14 pair_prepare ;;
 pair_block:
 {{ phase_start('exact') }}
 SET LR9 LR8 ; BGE.S LR2 CR0 pair_exact_left ;;
 ADD LR4 LR4 {{ cr.cin_or_panel }} ; INC LR9 {{ chunks }} ; BEQ LR15 CR0 pair_exact_center ;;
 pair_exact_left:
 {{ pair_tap('exact_left') }}
 pair_exact_center:
 {{ pair_tap('exact_center') }}
 {{ pair_tap('exact_right') }}
 ADD LR4 LR4 {{ cr.cin_or_panel }} ;;
 {{ phase_end('exact') }}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 INC LR13 1 ; INC LR3 1 ; ADD LR6 LR6 {{ cr.tail_or_block }} ;;
 BLT.S LR3 {{ cr.blocks }} pair_block ;;
 INC LR2 2 ; INC LR1 {{ 2 * chunks }} ; BEQ LR15 CR0 pair_ox ;;
 pair_prepare:
 SET LR8 LR1 ; SET LR5 LR0 ;;
 BGE.S LR5 CR0 pair_y_prepare ;;
 INC LR5 1 ; ADD LR8 LR8 {{ cr.input_pitch }} ;;
 pair_y_prepare:
 {{ prep('left', 0, 2 * chunks) }}
 {{ prep('right', 4 * chunks, 2 * chunks) }}
 {{ phase_end('prepare', 'pair_common') }}
 pair_common:
 {{ phase_start('common') }}
 SET LR9 LR8 ; ADD LR4 LR4 {{ cr.cin_or_panel }} ;;
 INC LR9 {{ 2 * chunks }} ; ADD LR4 LR4 {{ cr.cin_or_panel }} ;;
 ADD LR4 LR4 {{ cr.cin_or_panel }} ;;
 {{ pair_tap('common') }}
 {{ phase_end('common') }}
 ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.delta_or_scratch }} LR15 ;;
 LD.MULT R0 LR15 {{ cr.delta_or_scratch }} ; SET LR14 CR0 ;;
 MULT.VE LR15 CR1 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; INC LR14 1 ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.delta_or_scratch }} LR14 ;;
 {{ phase_start('left', resumed=true) }}
 SET LR9 LR8 ;;
 {{ pair_tap('left_diff', 1) }}
 {{ pair_tap('left_center') }}
 ADD LR4 LR4 {{ cr.cin_or_panel }} ;;
 ADD LR4 LR4 {{ cr.cin_or_panel }} ;;
 {{ phase_end('left') }}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 {{ phase_start('right', resumed=true) }}
 SET LR9 LR8 ; ADD LR4 LR4 {{ cr.cin_or_panel }} ;;
 INC LR9 {{ 3 * chunks }} ;;
 {{ pair_tap('right_center') }}
 {{ pair_tap('right_diff', -1) }}
 ADD LR4 LR4 {{ cr.cin_or_panel }} ;;
 {{ phase_end('right') }}
 ADD LR13 LR13 {{ cr.blocks }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 SUB LR13 LR13 {{ cr.blocks }} ; INC LR3 1 ; ADD LR6 LR6 {{ cr.tail_or_block }} ;;
 INC LR13 1 ; BLT.S LR3 {{ cr.blocks }} pair_common ;;
 ADD LR13 LR13 {{ cr.blocks }} ; INC LR2 4 ; INC LR1 {{ 4 * chunks }} ;;
 BLT.S LR2 {{ cr.xend }} pair_ox ;;
 {{ shift('LR1', (2 * w - 2 * out0_d3) * chunks) }}
 INC LR0 2 ;;
 BLT.S LR0 {{ cr.yend }} pair_oy ;;
 HALT ;;
{% elif fast %}
 INC LR12 128 ; DEC LR0 1 ; SET LR8 {{ cr.xend }} ;;
 DEC LR8 1 ;;
 fast_y:
 SET LR2 CR0 ; ADD LR7 LR0 CR0 ;;
 DEC LR2 1 ; INC LR7 2 ;;
 fast_x:
 SET LR3 CR0 ; SET LR4 CR0 ;;
 fast_block:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; SET LR14 LR1 ; SET LR5 LR0 ;;
 MULT.RC.VE LR15 {{ 'CR1' if bias else 'CR0' }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR4 1 ; BLT.S LR0 CR0 fast_top ;;
 fast_ky:
 SET LR9 LR14 ; BLT.S LR2 CR0 fast_left ;;
 {{ fast_tap() }}
 fast_center:
 {{ fast_tap() }}
 BGE.S LR2 LR8 fast_right ;;
 {{ fast_tap() }}
 fast_next:
 INC LR5 1 ; ADD LR14 LR14 {{ cr.input_pitch }} ; BGE.S LR5 LR7 fast_store ;;
 BLT.S LR5 {{ cr.in0_d2 }} fast_ky ;;
 fast_store:
{% if cout > 128 %}
 INC LR3 1 ;;
 BGE.S LR3 {{ cr.blocks }} fast_tail ;;
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 INC LR13 1 ; BEQ LR15 CR0 fast_block ;;
 fast_tail:
{% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail_or_block }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 INC LR13 1 ; INC LR1 1 ; INC LR2 1 ;;
 BLT.S LR2 {{ cr.xend }} fast_x ;;
 ADD LR1 LR1 {{ cr.delta_or_scratch }} ; INC LR0 1 ;;
 BLT.S LR0 {{ cr.yend }} fast_y ;;
 HALT ;;
 fast_top:
 ADD LR4 LR4 {{ cr.cin_or_panel }} ; INC LR5 1 ; ADD LR14 LR14 {{ cr.input_pitch }} ;;
 ADD LR4 LR4 {{ cr.cin_or_panel }} ;;
 ADD LR4 LR4 {{ cr.cin_or_panel }} ; BEQ LR15 CR0 fast_ky ;;
 fast_left:
 ADD LR4 LR4 {{ cr.cin_or_panel }} ; INC LR9 1 ; BEQ LR15 CR0 fast_center ;;
 fast_right:
 ADD LR4 LR4 {{ cr.cin_or_panel }} ; BEQ LR15 CR0 fast_next ;;
{% else %}
 INC LR12 128 ; DEC LR0 {{ padding }} ;;
oy:
 SET LR2 CR0 ;;
 DEC LR2 {{ padding }} ;;
ox:
 SET LR3 CR0 ; SET LR4 CR0 ;;
block:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 MULT.RC.VE LR15 {{ 'CR1' if bias else 'CR0' }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR5 CR0 ; SET LR14 LR1 ; INC LR4 1 ;;
ky:
 SET LR6 CR0 ;;
kx:
 ADD LR7 LR0 LR5 ; ADD LR8 LR2 LR6 ;;
 BLT.S LR7 CR0 skip ;;
 BGE.S LR7 {{ cr.in0_d2 }} skip ;;
 BLT.S LR8 CR0 skip ;;
 BGE.S LR8 {{ cr.input_pitch }} skip ;;
 ADD LR9 LR14 LR6 ;;
{% if chunks > 1 %}
 SET LR7 LR9 ;;
{% for i in range(chunks - 1) %}
 ADD LR9 LR9 LR7 ;;
{% endfor %}
{% endif %}
{% if dot %}
 {{ dot_tap() }}
{% else %}
{% if chunks > 1 %}
 SET LR10 CR0 ; SET LR7 CR0 ;;
 INC LR7 {{ cin // 128 - 1 }} ;;
chunk_loop:
 {{ chunk(128) }}
 INC LR10 1 ; BLT.S LR10 LR7 chunk_loop ;;
{% endif %}
{% if cin % 128 %}
 {{ chunk(panel if chunks == 1 else panel % 128) }}
{% endif %}
{% endif %}
 BEQ LR15 CR0 next ;;
skip:
 ADD LR4 LR4 {{ cr.cin_or_panel }} ;;
next:
 INC LR6 1 ; SET LR7 CR0 ;;
 INC LR7 {{ kw }} ;;
 BLT.S LR6 LR7 kx ;;
 INC LR5 1 ; SET LR7 CR0 ; ADD LR14 LR14 {{ cr.input_pitch }} ;;
 INC LR7 {{ kh }} ;;
 BLT.S LR5 LR7 ky ;;
 INC LR3 1 ;;
 BLT.S LR3 {{ cr.blocks }} fullstore ;;
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail_or_block }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 INC LR13 1 ; BEQ LR15 CR0 advance ;;
fullstore:
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 INC LR13 1 ; BEQ LR15 CR0 block ;;
advance:
 INC LR1 {{ stride }} ; INC LR2 {{ stride }} ;;
 BLT.S LR2 {{ cr.xend }} ox ;;
 ADD LR1 LR1 {{ cr.delta_or_scratch }} ; INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.yend }} oy ;;
 HALT ;;
{% endif %}
