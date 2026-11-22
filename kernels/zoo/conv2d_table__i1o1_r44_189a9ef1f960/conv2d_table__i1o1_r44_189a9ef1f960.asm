{% set chunks = (out0_d1 + 127) // 128 %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set act = act_out0 if act_out0 in ['identity', 'relu', 'relu6'] else 'generic' %}
{% macro adjust(r, delta) %}
{% for i in range(0, delta|abs, 255) %}
 {{ 'INC' if delta > 0 else 'DEC' }} {{ r }} {{ [255, delta|abs-i]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro store(d) %}
 ACTIVATE.QUANTIZE {{ act }} {{ d }} {{ qo }} {{ cr.out0 }} LR8 ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR13 CR0 ;;
{% if act == 'generic' %}
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ;;
 INC LR13 1 ;;
{% endfor %}
{% endif %}

{# LR1/LR2: output y/x; LR3/LR4: unpadded window origin y/x.
   LR5/LR6: input window origin row address / y-only row address.
   LR7: weight block; LR8: output row; LR9: channel chunk. #}
 SET LR1 CR0 ; SET LR3 CR0 ; SET LR6 CR0 ;;
 SET LR8 CR0 ;;
 {{ adjust('LR3', -padding) }}
 {{ adjust('LR6', -padding * in0_d3 * chunks) }}
y_loop:
 SET LR2 CR0 ; SET LR4 CR0 ; SET LR5 LR6 ;;
 {{ adjust('LR4', -padding) }}
 {{ adjust('LR5', -padding * chunks) }}
x_loop:
 SET LR9 CR0 ; SET LR7 CR0 ;;
chunk_loop:
 SET LR13 LR7 ; SET LR10 LR3 ; ADD LR11 LR5 LR9 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; INC LR13 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR13 1 ;;
{% macro filter_row(ky) %}
 BLT.S LR10 CR0 skip_y{{ ky }} ;;
 BGE.S LR10 {{ cr.in0_d2 }} skip_y{{ ky }} ;;
 SET LR12 LR4 ; SET LR14 LR11 ;;
{% for kx in range(kw) %}
 BLT.S LR12 CR0 skip_x{{ ky }}_{{ kx }} ;;
 BGE.S LR12 {{ cr.in0_d3 }} skip_x{{ ky }}_{{ kx }} ;;
 LD.MULT R0 LR14 {{ cr.in0 }} ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR13 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
 BEQ CR0 CR0 next_x{{ ky }}_{{ kx }} ;;
skip_x{{ ky }}_{{ kx }}:
 INC LR13 1 ;;
next_x{{ ky }}_{{ kx }}:
 INC LR13 1 ; INC LR12 1 ; INC LR14 {{ chunks }} ;;
{% endfor %}
 BEQ CR0 CR0 next_y{{ ky }} ;;
skip_y{{ ky }}:
 INC LR13 {{ 2 * kw }} ;;
next_y{{ ky }}:
 INC LR10 1 ; ADD LR11 LR11 {{ cr.pitch }} ;;
{% endmacro %}
{% for ky in range(kh) %}
 {{ filter_row(ky) }}
{% endfor %}
{% if chunks > 1 %}
 SET LR15 CR0 ;;
 INC LR15 {{ chunks - 1 }} ;;
 BEQ LR9 LR15 tail ;;
 {{ store(ds) }}
 INC LR9 1 ; INC LR8 1 ; INC LR7 {{ 2 * (1 + kh * kw) }} ; BEQ CR0 CR0 chunk_loop ;;
tail:
{% endif %}
 {{ store(cr.ds_tail ~ '.L') }}
 INC LR8 1 ; INC LR2 1 ; INC LR4 {{ stride }} ;;
 INC LR5 {{ stride * chunks }} ;;
 BLT.S LR2 {{ cr.out0_d3 }} x_loop ;;
 INC LR1 1 ; INC LR3 {{ stride }} ;;
{% for i in range(stride) %}
 ADD LR6 LR6 {{ cr.pitch }} ;;
{% endfor %}
 BLT.S LR1 {{ cr.out0_d2 }} y_loop ;;
 HALT ;;
