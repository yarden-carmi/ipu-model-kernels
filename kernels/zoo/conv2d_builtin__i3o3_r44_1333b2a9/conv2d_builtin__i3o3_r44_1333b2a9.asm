{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set pack = 2 if out0_d3 <= 64 else 1 %}
{% set chunks = (in0_d3 + 127) // 128 %}
{% set split = stride == 2 and chunks == 2 and pack == 1 %}
{% set step = 2 if split else 1 %}
{% set pitch = kw * step %}
{% macro move(reg, delta) %}
{% for n in range(0, delta | abs, 255) %}
 {{ 'INC' if delta > 0 else 'DEC' }} {{ reg }} {{ [255, (delta | abs) - n] | min }} ;;
{% endfor %}
{% endmacro %}

{# Stage horizontal windows once, including horizontal zero padding. #}
 SET LR14 LR0 ; SET LR15 LR1 ; SET LR4 CR0 ;;
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR8 CR0 ; SET LR9 CR0 ; INC LR7 128 ;;
 {{ move('LR8', 256) }}
 {{ move('LR9', 384) }}
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR4 ;;
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR9 ;;
{% if chunks == 1 %}
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR8 ;;
{% endif %}
prepare:
 LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR7 ; SET LR10 LR7 ;;
{% if chunks == 2 %}
 LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR8 ; INC LR5 1 ;;
{% endif %}
 INC LR5 1 ;;
{% if in0_d3 % 128 %}
{% set last = 'LR8' if chunks == 2 else 'LR7' %}
 SET LR13 {{ cr.scratch_rows }} ;;
 MULT.RC.VE {{ last }} CR1 0 LR4 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.line_ds }}.H {{ qi }} {{ cr.windows }} LR13 ;;
 LD.MULT.CYCLIC LR13 {{ cr.windows }} {{ last }} ;;
{% endif %}
{% if split %}
 SET LR10 LR7 ; SET LR11 LR8 ; SET LR12 CR1 ;;
 INC LR12 1 ;;
{% for x in range(kw) %}
 {% set mode = 'on_inv' if (x - padding) % 2 else 'on' %}
 MULT.RC.VE LR7 CR0 0 LR4 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR10 CR1 0 LR4 {{ full }} {{ qi }} ; ACC.STRIDE 64 {{ mode }} off LR12 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.windows }} LR6 ;;
 MULT.RC.VE LR11 CR0 0 LR4 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR6 1 ;;
 MULT.RC.VE LR11 CR1 0 LR4 {{ full }} {{ qi }} ; ACC.STRIDE 64 {{ mode }} off LR4 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.windows }} LR6 ;;
 INC LR6 1 ;;
{% endfor %}
{% else %}
 {{ move('LR10', -padding) }}
 SET LR13 CR0 ;;
 INC LR13 {{ kw }} ;;
window:
{% if stride == 1 %}
 MULT.RC.VE LR10 CR1 0 LR4 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
{% else %}
 SET LR0 LR14 ; SET LR1 LR15 ; SET LR11 LR10 ;;
 SET LR12 CR0 ;;
{% if out0_d3 // 8 %}
 INC LR12 {{ out0_d3 // 8 }} ;;
gather:
 MULT.RC.VE LR11 CR1 0 LR4 {{ full }} {{ qi }} ; ACC.RESHAPE LRD2 LRD0 0 ;;
 INC LR11 16 ; ADDBI LRD0 8 ;;
 DEC LR12 1 ;;
 BLT.S LR4 LR12 gather ;;
{% endif %}
{% if out0_d3 % 8 %}
 ADDBI LRD0 {{ out0_d3 % 8 - 8 }} ; DEC LR11 {{ 2 * (8 - out0_d3 % 8) }} ;;
 MULT.RC.VE LR11 CR1 0 LR4 {{ full }} {{ qi }} ; ACC.RESHAPE LRD2 LRD0 {{ 8 - out0_d3 % 8 }} ;;
{% endif %}
{% endif %}
 ACTIVATE.QUANTIZE identity {{ cr.line_ds }}.L {{ qi }} {{ cr.windows }} LR6 ; INC LR10 1 ; DEC LR13 1 ;;
 INC LR6 1 ; BLT.S LR4 LR13 window ;;
{% endif %}
 BLT.S LR6 {{ cr.scratch_rows }} prepare ;;

{% if pack == 2 %}
{# Right-align a copy of each staged line so two aligned cyclic loads
   can be consumed as one contiguous vector without requantizing the pair. #}
 SET LR5 CR0 ; SET LR10 CR0 ;;
 INC LR10 {{ out0_d3 }} ;;
align_window:
 LD.MULT.CYCLIC LR5 {{ cr.windows }} LR7 ;;
 MULT.RC.VE LR10 CR1 0 LR4 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR5 1 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.windows }} LR6 ;;
 INC LR6 1 ; BLT.S LR5 {{ cr.scratch_rows }} align_window ;;
{% endif %}

{# Each physical output row holds one or two complete spatial lines.
   A pair straddles the boundary between two aligned cyclic slots. #}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR14 CR0 ;;
{% if pack == 2 or split %}
 SET LR13 CR0 ;;
 INC LR13 128 ;;
{% endif %}
batch:
 SET LR4 CR1 ;;
channel:
 SET LR2 CR0 ; SET LR3 LR14 ; SET LR15 CR0 ;;
 ADD LR3 LR3 {{ cr.batch_pitch }} ;;
 SUB LR3 LR3 {{ cr.plane }} ;;
 {{ move('LR2', -padding) }}
 {{ move('LR3', -padding * pitch) }}
 {{ move('LR15', out0_d2 // pack) }}
row:
 SET LR5 LR4 ; SET LR6 LR2 ; SET LR7 LR3 ;;
 SET LR8 CR0 ;;
 {{ move('LR8', cin) }}
 MULT.EE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
ic:
 LD.MULT R0 LR5 {{ cr.weights }} ; SET LR9 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
 INC LR5 1 ; INC LR11 128 ; INC LR9 {{ kh }} ;;
ky:
{% if pack == 2 %}
 SET LR12 LR6 ;;
 INC LR12 {{ stride }} ;;
{% endif %}
 BLT.S LR6 CR0 first_invalid ;;
 BGE.S LR6 {{ cr.in0_d2 }} first_invalid ;;
{% macro load_first() %}
{% if pack == 2 %}
 ADD LR12 LR7 {{ cr.scratch_rows }} ;;
 LD.MULT.CYCLIC LR12 {{ cr.windows }} LR0 ; INC LR7 1 ;;
{% else %}
 LD.MULT.CYCLIC LR7 {{ cr.windows }} LR0 ;;
{% endif %}
{% endmacro %}
{% macro load_second(valid) %}
{% if valid %}
 SET LR12 LR7 ;;
{% if stride * kw > 1 %}
 LD.MULT.CYCLIC LR12 {{ cr.windows }} LR13 ; INC LR12 {{ stride * kw - 1 }} ;;
{% else %}
 LD.MULT.CYCLIC LR12 {{ cr.windows }} LR13 ;;
{% endif %}
{% else %}
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR13 ;;
{% endif %}
{% endmacro %}
{% macro digits(vec, extra='') %}
 MULT.RC.VE {{ vec }} LR10 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT R1 LR5 {{ cr.weights }} ; INC LR10 1{{ extra }} ;;
 MULT.RC.VE {{ vec }} LR11 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT R1 LR5 {{ cr.weights }} ; INC LR5 1 ; INC LR11 1 ;;
 MULT.RC.VE {{ vec }} LR11 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; DEC LR5 1 ;;
{% endmacro %}
{% macro taps(first, second) %}
{% for x in range(kw) %}
{% if split %}
 LD.MULT.CYCLIC LR7 {{ cr.windows }} LR0 ; SET LR12 CR0 ;;
 LD.MULT.CYCLIC LR7 {{ cr.windows }} LR13 ; INC LR7 1 ; INC LR12 {{ 64 + (x - padding) // 2 }} ;;
 {{ digits('LR12', ' ; INC LR7 1') }}
{% else %}
{% if first %}
 {{ load_first() }}
{% else %}
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ; INC LR7 1 ;;
{% endif %}
{% if pack == 2 %}
 {{ load_second(second) }}
 SET LR12 LR13 ;;
{% endif %}
 {{ digits('LR12', ' ; DEC LR12 ' ~ out0_d3) if pack == 2 else digits('LR0', ' ; INC LR7 1') }}
{% endif %}
{% endfor %}
{% endmacro %}
{% if pack == 2 %}
 BGE.S LR12 {{ cr.in0_d2 }} first_only ;;
 {{ taps(true, true) }}
 BEQ LR0 CR0 next_ky ;;
first_only:
 {{ taps(true, false) }}
{% else %}
 {{ taps(true, false) }}
{% endif %}
 BEQ LR0 CR0 next_ky ;;
first_invalid:
{% if pack == 2 %}
 BLT.S LR12 CR0 skip_ky ;;
 BGE.S LR12 {{ cr.in0_d2 }} skip_ky ;;
 {{ taps(false, true) }}
 BEQ LR0 CR0 next_ky ;;
skip_ky:
{% endif %}
 INC LR7 {{ pitch }} ; INC LR10 {{ kw }} ; INC LR11 {{ kw }} ;;
next_ky:
 INC LR6 1 ; DEC LR9 1 ;;
 BLT.S LR0 LR9 ky ;;
 SUB LR7 LR7 {{ cr.plane }} ; SET LR6 LR2 ; DEC LR8 1 ;;
 DEC LR7 {{ kh * pitch }} ; INC LR5 2 ;;
 BLT.S LR0 LR8 ic ;;
{% if bias %}
 LD.MULT R0 LR4 {{ cr.weights }} ; SET LR11 CR0 ; SET LR12 LR4 ;;
 LD.MULT R1 LR12 {{ cr.weights }} ; INC LR12 1 ; INC LR11 128 ; MULT.EE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 MULT.EE LR11 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT R1 LR12 {{ cr.weights }} ; INC LR12 1 ;;
 MULT.EE LR11 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
{% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.packed_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; DEC LR15 1 ;;
 INC LR2 {{ stride * pack }} ; INC LR3 {{ stride * pack * pitch }} ; INC LR1 1 ;;
 BLT.S LR0 LR15 row ;;
 SET LR4 LR5 ; BLT.S LR5 {{ cr.weight_rows }} channel ;;
 ADD LR14 LR14 {{ cr.batch_pitch }} ;;
 BLT.S LR14 {{ cr.scratch_rows }} batch ;;
 HALT ;;
