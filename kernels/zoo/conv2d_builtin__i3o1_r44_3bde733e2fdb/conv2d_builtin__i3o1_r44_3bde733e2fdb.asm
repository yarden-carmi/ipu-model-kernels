{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = qi %}
{% set full = cr.full ~ '.L' %}
{% set ib = (in0_d1 + 127) // 128 %}
{% set ob = (out0_d1 + 127) // 128 %}
{% set depthwise = groups == in0_d1 and groups == out0_d1 %}
{% macro offset(reg, value) %}
{% for n in range(0, value | abs, 255) %}
    {{ 'INC' if value > 0 else 'DEC' }} {{ reg }} {{ [255, (value | abs) - n] | min }} ;;
{% endfor %}
{% endmacro %}
{# Transpose the producer's packed spatial planes into channel vectors. #}
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; DEC LR13 1 ;;
transpose_pixel:
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    SET LR4 LR8 ; SET LR5 CR0 ;;
    MULT.EE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
transpose_channel:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.EE LR6 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR4 LR4 LR15 ;;
    ADDBI LRD2 1 ; INC LR5 1 ; BLT.S LR5 LR13 transpose_channel ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ qw }} {{ cr.transposed }} LR7 ;;
    {# Recover the rounding residual per channel before transposing it. #}
    LD.MULT R1 LR7 {{ cr.transposed }} ;;
    SET LR4 LR8 ; SET LR5 CR0 ; SET LR10 CR0 ;;
    INC LR10 128 ; SET LR11 LR13 ;;
    DEC LR11 1 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    BEQ LR13 CR0 residual_last ;;
residual_channel:
    MULT.EE LR6 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ADD LR4 LR4 LR15 ;;
    MULT.EE LR10 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.SUB ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.H {{ qi }} {{ cr.scalar }} LR5 ;;
    INC LR5 1 ; INC LR10 1 ; BLT.S LR5 LR11 residual_channel ;;
residual_last:
    MULT.EE LR6 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
    MULT.EE LR10 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.H {{ qi }} {{ cr.scalar }} LR5 ;;
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    MULT.EE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
residual_gather:
    LD.MULT R0 LR5 {{ cr.scalar }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADDBI LRD2 1 ; INC LR5 1 ; BLT.S LR5 LR13 residual_gather ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.residual }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ; INC LR9 1 ;;
    SET LR10 CR0 ;;
    INC LR10 128 ;;
    BLT.S LR6 LR10 transpose_nowrap ;;
    SET LR6 CR0 ; INC LR8 1 ;;
transpose_nowrap:
    BLT.S LR9 LR14 transpose_pixel ;;
{% if false %}
{% macro loadtap(tap, slot) %}
 {% set dy, dx = tap %}
 {{ ['SUB','SET','ADD'][dx+1] }} LR6 {{ ['LR4','LR3','LR5'][dy+1] }}{{ ' CR1' if dx else '' }} ; LD.MULT.CYCLIC LR6 {{ cr.staged if slot == 'LR0' else cr.in0 }} {{ slot }}
{% endmacro %}
{% macro pair(tag, taps) %}
 {{ loadtap(taps[0], 'LR0') }} ; SET LR8 LR15 ;;
 {% if taps|length == 2 %}{{ loadtap(taps[1], 'LR11') }} ;;{% endif %}
 dot_{{ tag }}:
 MULT.RC.VV LR12 R0 0 LR0 {{ full }} {{ qi }} ; AGG.SUM LR8 {{ full }} ; INC LR8 1 ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.weights }} ; BLT.S LR8 {{ cr.v12 }} dot_{{ tag }} ;;
{% endmacro %}
{% macro pixel(y, x) %}
 {% set tag = (y+1) ~ '_' ~ (x+1) %}
 {% set idx = (y+1)*3+x+1 %}
 {% set starts = ['CR0', 'LR9', 'LR10', 'LR13', 'LR14', cr.full ~ '.H', cr.tail ~ '.H', cr.offsets ~ '.L', cr.offsets ~ '.H'] %}
 {% set taps = [] %}
 {% for dy in [-1,0,1] if not y or dy != y %}
 {% for dx in [-1,0,1] if not x or dx != x %}
 {% set unused = taps.append((dy,dx)) %}
 {% endfor %}
 {% endfor %}
 pixel_{{ tag }}:
 SET LR7 {{ starts[idx] }} ; LD.MULT.CYCLIC LR0 {{ cr.weights }} LR11 ;;
 MULT.RC.VE LR11 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.weights }} ;;
 {% for i in range(0,taps|length,2) %}{{ pair(tag ~ '_' ~ i, taps[i:i+2]) }}{% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; BEQ LR0 CR0 advance ;;
{% endmacro %}
{% macro dispatch(y) %}
 BEQ LR2 CR0 pixel_{{ y+1 }}_0 ;;
 BEQ LR2 {{ cr.v9 }} pixel_{{ y+1 }}_2 ;;
 {% if in0_d3 > 2 %}{{ pixel(y,0) }}{% endif %}
 {{ pixel(y,-1) }}
 {{ pixel(y,1) }}
{% endmacro %}
 INC LR11 128 ; INC LR12 64 ; DEC LR15 1 ;;
 SET LR3 LR15 ;;
 stage:
 LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR11 ; INC LR3 1 ;;
 MULT.RC.VE LR12 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.staged }} LR3 ; BLT.S LR3 {{ cr.v13 }} stage ;;
 SET LR3 CR0 ;;
 row:
 SET LR2 CR0 ;;
 col:
 SUB LR4 LR3 {{ cr.v11 }} ; ADD LR5 LR3 {{ cr.v11 }} ; BEQ LR1 CR0 top ;;
 BEQ LR1 {{ cr.v10 }} bottom ;;
 {% if in0_d2 > 2 %}{{ dispatch(0) }}{% endif %}
 top:
 {{ dispatch(-1) }}
 bottom:
 {{ dispatch(1) }}
 advance:
 INC LR3 1 ; INC LR2 1 ; BLT.S LR2 {{ cr.v9 }} col ;;
 INC LR1 1 ; BLT.S LR1 {{ cr.v10 }} row ;;
 HALT ;;
{% else %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR12 CR0 ;;
    {{ offset('LR2', -padding) }}
    {{ offset('LR12', -padding * (in0_d3 + 1) * ib) }}
out_y:
    SET LR3 CR0 ; SET LR10 CR0 ;;
    {{ offset('LR3', -padding) }}
out_x:
{% for b in range(ob) %}
    SET LR5 CR0 ; SET LR14 CR0 ;;
    {{ offset('LR5', b * (2 + kh * kw * (1 if depthwise else in0_d1) * 2)) }}
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ; MULT.RC.VE LR14 CR1 0 LR0 {{ full }} {{ qw }} ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ; MULT.RC.VE LR14 CR1 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ;;
    SET LR6 LR2 ; SET LR4 LR12 ; SET LR11 CR0 ;;
ky_{{b}}:
    SET LR7 LR3 ; SET LR9 LR4 ; SET LR13 CR0 ;;
kx_{{b}}:
    BLT.S LR6 CR0 skip_{{b}} ;;
    BGE.S LR6 {{ cr.v9 }} skip_{{b}} ;;
    BLT.S LR7 CR0 skip_{{b}} ;;
    BGE.S LR7 {{ cr.v10 }} skip_{{b}} ;;
{% if depthwise %}
    {{ offset('LR9', b) }}
    LD.MULT R0 LR9 {{ cr.transposed }} ;;
    LD.MULT R1 LR9 {{ cr.residual }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ; MULT.RC.VV LR14 R0 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ;;
    MULT.RC.VV LR14 R1 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ;;
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ; MULT.RC.VV LR14 R0 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ;;
    MULT.RC.VV LR14 R1 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ;;
    {{ offset('LR9', -b) }}
{% else %}
{% for c in range(ib) %}
    LD.MULT R0 LR9 {{ cr.transposed }} ; SET LR8 CR0 ;;
    LD.MULT R1 LR9 {{ cr.residual }} ;;
    SET LR15 CR0 ;; {{ offset('LR15', [128, in0_d1 - c * 128] | min - 1) }}
{% if c > 0 and in0_d1 - c * 128 < 128 %}
    SET LR15 CR0 ;; {{ offset('LR15', in0_d1 - c * 128 - 1) }}
{% endif %}
ic_{{b}}_{{c}}:
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ; MULT.RC.VE LR14 LR8 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ;;
    INC LR8 128 ;;
    MULT.RC.VE LR14 LR8 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ;;
    DEC LR8 128 ;;
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ; MULT.RC.VE LR14 LR8 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ;;
    INC LR8 128 ;;
    MULT.RC.VE LR14 LR8 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ;;
    DEC LR8 128 ;;
    INC LR8 1 ; BLT.S LR8 LR15 ic_{{b}}_{{c}} ;;
{% if not loop.last %}
    INC LR9 1 ;;
{% endif %}
{% endfor %}
    {{ offset('LR9', 1 - ib) }}
{% endif %}
    B tap_end_{{b}} ;;
skip_{{b}}:
    {{ offset('LR5', 2 * (1 if depthwise else in0_d1)) }}
tap_end_{{b}}:
    INC LR7 1 ; INC LR13 1 ; {{ offset('LR9', ib) }}
    BLT.S LR13 {{ cr.v12 }} kx_{{b}} ;;
    INC LR6 1 ; INC LR11 1 ; {{ offset('LR4', in0_d3 * ib) }}
    BLT.S LR11 {{ cr.v11 }} ky_{{b}} ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail ~ '.L' if b == ob-1 else full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endfor %}
    INC LR10 1 ; {{ offset('LR3', stride) }}{{ offset('LR12', stride * ib) }}
    SET LR15 CR0 ;; {{ offset('LR15', out0_d3) }}
    BLT.S LR10 LR15 out_x ;;
    {{ offset('LR12', stride * ib * (in0_d3 - out0_d3)) }}
    {{ offset('LR2', stride) }}
    SET LR15 CR0 ;; {{ offset('LR15', out0_d2 * stride - padding) }}
    BLT.S LR2 LR15 out_y ;;
    HALT ;;
{% endif %}
