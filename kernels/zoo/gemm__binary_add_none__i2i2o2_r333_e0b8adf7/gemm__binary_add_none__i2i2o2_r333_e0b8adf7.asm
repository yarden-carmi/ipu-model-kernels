{% set tiles = (out0_d2 + 127) // 128 %}
{% set rtiles = (in1_d2 + 127) // 128 %}
{% set chunks = (s0_k + 127) // 128 %}
{% set flat = s0_m % 64 == 0 and (in1_d1 * in1_d2) % 128 == 0 and in1_d2 % 2 == 0 %}
{% set tail = (out0_d2 - 1) % 128 + 1 %}
{% set bound = cr.slot if flat else cr.res_bound %}
{% set rowstep = 1 if flat else rtiles %}
{% set paired = flat and 128 % s0_m == 0 and s0_m % 64 == 0 and s0_m < 128 %}
{% set dot_tail = tiles > 1 and chunks <= 4 and tail * (chunks + 2) < s0_k %}
{% macro scatter(src) %}
    MULT.EE {{src}} CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD14 7
{%- endmacro %}
{% macro flat_even(first=false) %}
    {{ scatter('LR12') }} ; LD.MULT R0 LR3 {{ cr.in1 }} ; ADD LR3 LR3 {{ cr.stepq }} {% if not first %}; ADDBI LRD14 1{% endif %}; BNE LR2 CR0 flat_odd ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ds}}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
{% macro reduction_chunk(i) %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    DEC LR3 1 ; INC LR4 {{ 126 if i < chunks - 1 else (s0_k - 1) % 128 + 1 }} ;;
{% if i == chunks - 1 %}
    DEC LR4 2 ;;
{% endif %}
lane_{{i}}:
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR14 {{ cr.w }} LR0 ; INC LR14 1 ; INC LR3 1 ; BLT.S LR3 LR4 lane_{{i}} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ;;
    SET LR7 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    DEC LR5 1 ; DEC LR8 1 ; SET LR10 CR0 ;;
batch:
    SET LR13 CR0 ;;
{% for i in range(0, out0_d1, 255) %}
    INC LR13 {{ [255,out0_d1-i]|min }} ;;
{% endfor %}
row:
    SET LR6 CR0 ; SET LR11 LR9 ; SET LR12 LR10 ;;
    INC LR6 {{tiles}} ;;
tile:
    SET LR2 {{ cr.slot }} ; DEC LR6 1 ;;
    BNE LR6 CR0 gather ;;
    SET LR2 CR0 ;;
    INC LR2 {{tail}} ;;
{% if paired %}
gather:
    SET LR4 LR2 ; SET LR2 CR0 ; SET LR3 {{cr.stepq}} ;;
    ADDB LRD2 LR12 ; SET LR14 CR0 ; SET LR15 {{cr.stepr}} ;;
    DEC LR4 2 ; LD.MULT R0 LR11 {{cr.in1}} ;;
    BEQ LR4 CR0 pair_single ;;
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.RESHAPE LRD2 LRD14 6 ; LD.MULT R0 LR11 {{cr.in1}} ; INC LR11 1 ; DEC LR4 2 ;;
    BEQ LR4 CR0 pair_last ; DEC LR4 2 ;;
pair_loop:
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.RESHAPE LRD2 LRD14 6 ; ADDBI LRD14 2 ; LD.MULT R0 LR11 {{cr.in1}} ; INC LR11 1 ; DEC LR4 2 ; BNE LR4 CR0 pair_loop ;;
pair_last:
    ADDBI LRD14 2 ;;
pair_single:
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.RESHAPE LRD2 LRD14 6 ; INC LR11 1 ;;
{% elif flat and tail % 2 == 0 %}
{# Packed storage removes per-position padding. Two residual streams, each
   with a fixed lane and a row stride of 2*M/128, feed alternate destinations. #}
gather:
    ADD LR3 LR11 {{ cr.stepr }} ; SET LR4 LR12 ; DEC LR2 2 ; LD.MULT R0 LR11 {{ cr.in1 }} ;;
{% if s0_m % 128 %}
    BLT.S LR4 {{ cr.res_bound }} flat_low ;;
    INC LR3 1 ;;
flat_low:
    INC.MODP2 LR4 {{ cr.res_bound }} 7 ;;
{% endif %}
    SUB LR3 LR3 {{ cr.stepq }} ; SET LR14 CR0 ; SET LR15 CR0 ;;
{{ flat_even(true) }}
    B flat_last ;;
flat_odd:
    {{ scatter('LR4') }} ; ADDBI LRD14 1 ; ADD LR11 LR11 {{ cr.stepq }} ; DEC LR2 2 ; LD.MULT R0 LR11 {{ cr.in1 }} ;;
{{ flat_even() }}
flat_last:
    {{ scatter('LR4') }} ; ADDBI LRD14 1 ; ADD LR11 LR11 {{ cr.stepq }} ;;
{% else %}
{# Quotient and remainder of residual view address b+B*p+M*c. #}
gather:
    SET LR14 CR0 ; SET LR15 CR0 ;;
{% if flat %}
{# Single-element fallback for an odd output width. #}
    LD.MULT R0 LR11 {{ cr.in1 }} ; DEC LR2 1 ;;
    {{ scatter('LR12') }} ; ADD LR11 LR11 {{ cr.stepr }} {% if s0_m % 128 %}; BLT.S LR12 {{ cr.res_bound }} flat_no_carry{% endif %} ;;
{% if s0_m % 128 %}
    INC LR11 1 ;;
flat_no_carry:
    INC.MODP2 LR12 {{ cr.res_bound }} 7 ;;
{% endif %}
    ADDBI LRD14 1 ; BNE LR2 CR0 gather ;;
{% else %}
    SET LR3 LR11 ; SET LR4 LR12 {% if rtiles > 1 %}; BLT.S LR12 {{ cr.slot }} load_residual{% endif %} ;;
{% for i in range(1, rtiles) %}
    INC LR3 1 ; SUB LR4 LR4 {{ cr.slot }} {% if i < rtiles - 1 %}; BLT.S LR4 {{ cr.slot }} load_residual{% endif %} ;;
{% endfor %}
load_residual:
    LD.MULT R0 LR3 {{ cr.in1 }} ; ADD LR11 LR11 {{ cr.stepq }} ; ADD LR12 LR12 {{ cr.stepr }} ; DEC LR2 1 ;;
    {{ scatter('LR4') }} ; BLT.S LR12 {{ cr.res_bound }} gathered ;;
    SUB LR12 LR12 {{ cr.res_bound }} ; INC LR11 {{rtiles}} ;;
gathered:
    ADDBI LRD14 1 ; BNE LR2 CR0 gather ;;
{% endif %}
{% endif %}
    SET LR14 CR0 ; SET LR4 CR0 ;;
    DEC LR14 1 {% if tiles > 1 %}; INC LR4 {{tiles - 1}}{% endif %} ;;
{% if tiles > 1 %}
weight_tile:
    BEQ LR4 LR6 weight_ready ;;
    ADD LR14 LR14 {{ cr.weight_stride }} ; DEC LR4 1 ; B weight_tile ;;
weight_ready:
{% endif %}
{% if dot_tail %}
    BEQ LR6 CR0 dot_reduce ;;
{% endif %}
    SET LR2 LR8 ; SET LR15 CR0 ;;
    LD.MULT.CYCLIC LR14 {{ cr.w }} LR0 ; INC LR14 1 ; INC LR15 {{chunks}} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR14 {{ cr.w }} LR0 ; INC LR14 1 ;;
{% if chunks <= 4 and s0_k > 1 and s0_k % 128 != 1 %}
{% for i in range(chunks) %}
{{ reduction_chunk(i) }}
{% endfor %}
{% else %}
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; DEC LR15 1 ; SET LR4 {{ cr.slot }} ;;
    DEC LR4 2 ; SET LR3 CR0 ; BNE LR15 CR0 start_lane ;;
    SET LR4 CR0 ;;
{% if (s0_k - 1) % 128 %}
    INC LR4 {{ (s0_k - 1) % 128 }} ;;
{% endif %}
    DEC LR4 1 ;;
start_lane:
    DEC LR3 1 ;;
lane:
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR14 {{ cr.w }} LR0 ; INC LR14 1 ; INC LR3 1 ; BLT.S LR3 LR4 lane ;;
    BNE LR15 CR0 chunk ;;
{% endif %}
    BEQ LR6 CR0 last_tile ;;
{{ store(cr.full) }}
    B tile ;;
{% if dot_tail %}
dot_reduce:
    LD.MULT R0 LR14 {{cr.w}} ; INC LR14 1 ; SET LR2 LR8 ; SET LR15 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ; SUB LR15 LR15 {{cr.slot}} ;;
{% for i in range(chunks) %}
    LD.MULT.CYCLIC LR2 {{cr.in0}} LR15 ; INC LR2 1 ; ADD LR15 LR15 {{cr.slot}} ;;
{% endfor %}
    SET LR3 CR0 ; SET LR4 CR0 ;;
    INC LR4 {{tail}} ; DEC LR3 1 ;;
    DEC LR4 {{ 2 if chunks == 1 else 1 }} ;;
dot_channel:
    SET LR15 CR0 ; LD.MULT R0 LR14 {{cr.w}} ; INC LR14 1 ;;
{% for i in range(chunks) %}
    MULT.RC.VV LR15 R0 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR3 {{cr.full}}.L {% if i == 0 %}; INC LR3 1{% else %}; ADD LR15 LR15 {{cr.slot}}{% endif %} {% if i + 1 < chunks %}; LD.MULT R0 LR14 {{cr.w}} ; INC LR14 1{% else %}; BLT.S LR3 LR4 dot_channel{% endif %} ;;
{% endfor %}
{% endif %}
last_tile:
{{ store(cr.tail) }}
    INC LR8 {{chunks}} ; DEC LR13 1 ;;
    BNE LR13 CR0 next_position ;;
    INC LR7 1 ; SET LR3 CR0 ;;
    INC LR3 {{out0_d0}} ;;
    BEQ LR7 LR3 done ;;
    SET LR9 CR0 ; SET LR10 LR7 ;;
normalize_batch:
    BLT.S LR10 {{ bound }} batch ;;
    SUB LR10 LR10 {{ bound }} ; INC LR9 {{rowstep}} ; B normalize_batch ;;
next_position:
    INC LR10 {{out0_d0}} ;;
normalize_position:
    BLT.S LR10 {{ bound }} row ;;
    SUB LR10 LR10 {{ bound }} ; INC LR9 {{rowstep}} ; B normalize_position ;;
done:
    HALT ;;
