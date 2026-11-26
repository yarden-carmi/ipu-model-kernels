{% set w = cr.w if bias else cr.w_unbiased %}
{% set spatial = in0_d2 * in0_d3 %}
{% set tiny = spatial == 64 and k % 2 == 0 and k <= 1024 %}
{% macro aq(base, row, ds, q, act='identity') %}ACTIVATE.QUANTIZE {{ act }} {{ ds }}.L {{ q }}.L {{ base }} {{ row }}{% endmacro %}
{% macro output(row) %}{{ aq(cr.out0, row, cr.active, cr.qf_out0, act_out0 | default('identity')) }}{% endmacro %}
{% macro coeff() %}INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ w }} LR0{% endmacro %}
{% macro mac(src, first=false) %}MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro seed(fetch=false) %}
{% if bias %}
    {{ coeff() }} ;;
    {{ mac('CR1', true) }} ; {{ coeff() }} ;;
    {{ mac('CR1') }} {% if fetch %}; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %} ;;
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST {% if fetch %}; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %} ;;
{% endif %}
{% endmacro %}
{% if not tiny %}
{# Each input vector spans a tile of pixels. Keep two tap rows resident
   and advance the input stream on the final digit of each tap. #}
{% set wide = k >= 256 and spatial > 1024 %}
{% set group = 96 if wide else 32 %}
{% set fix = 22 if spatial <= 256 else 24 if k >= 256 else 26 if k >= 128 else 24 if spatial >= 4096 else 32 %}
{% macro segment(start, taps, final, last) %}
{% for j in range(start, start + taps) %}
{% set dual = j % 8 != 3 if wide else j < fix %}
{% set fetch = not final or not (last and loop.last) %}
{% set repeat = not final and last and loop.last %}
{% set next = '; ADD LR6 LR6 LR4 ; LD.MULT.CYCLIC LR6 ' ~ cr.in0 ~ ' LR0' if fetch else '' %}
{% set branch = '; DEC LR14 1 ; BNE LR14 CR1 tap_block' if repeat else '' %}
    {{ mac('LR1') }} ; INC LR1 1 {% if not dual %}{% if not repeat %}; INC LR2 1{% endif %} {{ next }} {{ branch }}{% endif %} ;;
{% if dual %}
    {{ mac('LR2') }} ; INC LR2 1 {{ next }} {{ branch }} ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro block(taps, final=false) %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ; SET LR1 CR0 ; SET LR2 {{ cr.second }} ;;
    INC LR7 1 ; LD.MULT R1 LR7 {{ w }} ; DEC LR1 1 ; DEC LR2 1 ;;
    {{ segment(0, [32,taps]|min, final, taps <= 32) }}
{% if taps > 32 %}
    {{ segment(32, [32,taps-32]|min, final, taps <= 64) }}
{% endif %}
{% if taps > 64 %}
    {{ segment(64, taps-64, final, true) }}
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
    SET LR12 {{ cr.in0_d0 }} ; DEC LR5 1 ;;
batch:
    SET LR8 {{ cr.n }} ; SUB LR9 LR0 CR1 ;;
feature:
    SET LR10 LR11 ; SET LR13 LR4 ;;
tile:
    SET LR7 LR9 ; SET LR6 LR10 ; SET LR14 {{ cr.blocks }} ;;
    {{ seed(true) }}
{% if k > group %}
tap_block:
    {{ block(group) }}
{% endif %}
    {{ block((k-1)%group+1, true) }}
    {{ output('LR5') }} ; INC LR5 1 ; INC LR10 1 ; DEC LR13 1 ; BNE LR13 CR1 tile ;;
    SET LR9 LR7 ; DEC LR8 1 ; BNE LR8 CR1 feature ;;
    ADD LR11 LR11 LR15 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
{% else %}
{# For half-full planes, build a pixel-major panel once per batch so
   the dot products can use full vectors of taps instead. #}
{% set chunks = (k+127)//128 %}
{% macro pair_copy() %}MULT.VE LR4 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 6{% endmacro %}
{% macro gather(chunk, pairs) %}
    SET LR2 CR0 ; SET LR3 {{ cr.pair_dest }} ; SET LR10 CR0 ;;
    LD.MULT R0 LR8 {{ cr.panel }} {% if pairs > 2 %}; INC LR10 {{ pairs-2 }}{% endif %} ;;
{% if pairs > 1 %}
    {{ pair_copy() }} ; INC LR8 1 ; LD.MULT R0 LR8 {{ cr.panel }} ;;
{% if pairs > 2 %}
gather_{{ chunk }}:
    {{ pair_copy() }} ; INC LR8 1 ; DEC LR10 1 ; ADDBI LRD2 2 ; LD.MULT R0 LR8 {{ cr.panel }} ; BNE LR10 CR1 gather_{{ chunk }} ;;
{% endif %}
{% endif %}
    {{ pair_copy() }} ; INC LR8 1 {% if pairs > 1 %}; ADDBI LRD2 2{% endif %} ;;
    INC LR12 1 ; {{ aq(cr.panel, 'LR12', cr.tail if chunk == chunks-1 else cr.full, cr.qf_in0) }} ;;
{% endmacro %}
{% macro dot(tag) %}
    {{ coeff() }} ; SET LR10 LR12 ; SUB LR2 LR0 CR1 ;;
    LD.MULT R0 LR10 {{ cr.panel }} ; SET LR3 LR13 ;;
dot_{{ tag }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ cr.full }}.L ; INC LR10 {{ chunks }} ; INC LR2 1 ; DEC LR3 1 ; LD.MULT R0 LR10 {{ cr.panel }} ; BNE LR3 CR1 dot_{{ tag }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ cr.full }}.L ; INC LR2 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR11 CR0 ; SET LR6 CR0 ;;
    SET LR14 {{ cr.in0_d0 }} ; DEC LR6 1 ;;
tiny_batch:
    SET LR3 CR0 ; SET LR8 LR11 ; SET LR9 LR5 ;;
    INC LR3 64 ; DEC LR9 1 ; SET LR10 CR0 ;;
{% for j in range((k//2+127)//128) %}
    INC LR10 {{ [128,k//2-j*128] | min }} ;;
{% endfor %}
pack_pair:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    INC LR8 1 ; LD.MULT R1 LR8 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR8 1 ;;
    MULT.VE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1 ; {{ aq(cr.panel, 'LR9', cr.full, cr.qf_in0) }} ; DEC LR10 1 ; BNE LR10 CR1 pack_pair ;;
    SET LR1 {{ cr.second }} ; SET LR12 CR0 ; SET LR7 CR0 ;;
    SET LR4 CR0 ; INC LR7 64 ; DEC LR12 1 ;;
gather_pixel:
    SET LR8 LR5 ;;
{% for chunk in range(chunks) %}
    {{ gather(chunk, [64,k//2-64*chunk] | min) }}
{% endfor %}
    ADDBI LRD0 1 ; DEC LR7 1 ; BNE LR7 CR1 gather_pixel ;;
    SET LR0 CR0 ; SET LR9 {{ cr.n }} ; SET LR13 CR0 ;;
    SUB LR7 LR0 CR1 ; INC LR13 63 ;;
tiny_feature:
    {{ seed() }}
{% for chunk in range(chunks) %}
    SET LR12 CR0 ;;
{% if chunk %}
    INC LR12 {{ chunk }} ;;
{% endif %}
    {{ dot('high_' ~ chunk) }}
{% if bias and chunk == (2 if chunks >= 3 else 0) %}
    {{ dot('low_' ~ chunk) }}
{% endif %}
{% endfor %}
    {{ output('LR6') }} ; INC LR6 1 ; DEC LR9 1 ; BNE LR9 CR1 tiny_feature ;;
    ADD LR11 LR11 LR15 ; DEC LR14 1 ; BNE LR14 CR1 tiny_batch ;;
    HALT ;;
{% endif %}
