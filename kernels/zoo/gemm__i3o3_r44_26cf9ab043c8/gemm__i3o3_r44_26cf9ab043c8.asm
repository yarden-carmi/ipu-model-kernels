{% set w = cr.w if bias else cr.w_unbiased %}
{% set spatial = in0_d2 * in0_d3 %}
{% set tiny = spatial == 64 and k % 2 == 0 and k <= 1024 %}
{% macro aq(base, row, ds, q, act='identity') %}ACTIVATE.QUANTIZE {{ act }} {{ ds }}.L {{ q }}.L {{ base }} {{ row }}{% endmacro %}
{% macro out(row, ds) %}{{ aq(cr.out0, row, ds, cr.qf_out0, act_out0 | default('identity')) }}{% endmacro %}
{% macro coeff() %}INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ w }} LR0{% endmacro %}
{% macro mac(src, first=false) %}MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro seed() %}
{% if bias %}
    {{ coeff() }} ;;
    {{ mac('CR1', true) }} ; {{ coeff() }} ;;
    {{ mac('CR1') }} ;;
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
{% endmacro %}

{% if not tiny %}
{# Spatial positions fill the lanes; each tap broadcasts a resident scalar. #}
{% set c = [in0_d2, [1, 128 // in0_d3] | max] | min %}
{% set p = c if in0_d2 % c == 0 else 1 %}
{% set wide_tail = p * in0_d3 > 128 and (p * in0_d3) % 128 != 0 %}
{% set separate = spatial > 1024 %}
{% set long = separate and k >= 256 and k % 128 == 0 and (in0_d3 <= 128 or in0_d3 % 128 == 0) %}
{% set fix = (26 if k >= 128 else 22) if separate else (22 if spatial <= 256 else (24 if k >= 256 else (26 if k >= 128 else 32))) %}
{% macro next_input() %}ADD LR6 LR6 LR4 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endmacro %}
{% macro long_block(tag, final=false) %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ; SUB LR1 LR0 CR1 ; SET LR2 {{ cr.second }} ;;
    INC LR7 1 ; LD.MULT R1 LR7 {{ w }} ; DEC LR2 1 ; DEC LR3 18 ;;
dual_{{ tag }}:
    {{ mac('LR1') }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; INC LR2 1 ; {{ next_input() }} ; BLT.S LR1 LR3 dual_{{ tag }} ;;
    {{ mac('LR1') }} ; INC LR1 1 ; INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ; INC LR3 18 ;;
    {{ mac('LR2') }} ; INC LR2 1 ; {{ next_input() }} ;;
direct_{{ tag }}:
    {{ mac('LR1') }} ; INC LR1 1 ; {{ next_input() }} ; BLT.S LR1 LR3 direct_{{ tag }} ;;
    {{ mac('LR1') }} ; INC LR1 1 {% if not final %}; {{ next_input() }} ; DEC LR14 1 ; BNE LR14 CR1 tap_block{% else %}; INC LR7 1 ; LD.MULT R1 LR7 {{ w }}{% endif %} ;;
{% if final %}
    SUB LR2 LR10 LR11 ; LD.MULT.CYCLIC LR2 {{ cr.panel }} LR0 ;;
    SET LR2 {{ cr.second }} ; {{ mac('LR2') }} ;;
{% endif %}
{% endmacro %}
{% macro sum_direct() %}
    SET LR9 LR4 ;;
{# Form 110*pitch by binary doubling. #}
{% for bit in [1,0,1,1,1,0] %}
    ADD LR9 LR9 LR9 ;;
{% if bit %}
    ADD LR9 LR9 LR4 ;;
{% endif %}
{% endfor %}
    SET LR13 LR4 ; SET LR3 CR0 ; SUB LR10 LR11 LR4 ;;
sum_tile:
    SET LR6 LR10 ; SET LR14 {{ cr.blocks }} ;;
    INC LR14 1 ; MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
sum_chunk:
    ADD LR6 LR6 LR9 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; SET LR7 CR0 ;;
    INC LR7 18 ;;
sum_tap:
    {{ mac('CR1') }} ; {{ next_input() }} ; DEC LR7 1 ; BNE LR7 CR1 sum_tap ;;
    {{ mac('CR1') }} ; DEC LR14 1 ; BNE LR14 CR1 sum_chunk ;;
    {{ aq(cr.panel,'LR3',cr.active,cr.qf_in0) }} ;;
    INC LR3 1 ; INC LR10 1 ; DEC LR13 1 ; BNE LR13 CR1 sum_tile ;;
{% endmacro %}
{% macro block(taps, final=false) %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ; SET LR1 CR0 ; SET LR2 {{ cr.second }} ;;
    INC LR7 1 ; LD.MULT R1 LR7 {{ w }} ; DEC LR1 1 ; DEC LR2 1 ;;
{% for j in range(taps) %}
{% set dual = j < fix %}
{% set fetch = not final or not loop.last %}
{% set repeat = not final and loop.last %}
    {{ mac('LR1') }} ; INC LR1 1 {% if separate and j == fix - 1 and taps > fix %}; INC LR7 1 ; LD.MULT R0 LR7 {{ w }}{% endif %}{% if not dual %}{% if not repeat %}; INC LR2 1{% endif %} {% if fetch %}; {{ next_input() }}{% endif %}{% if repeat %}; DEC LR14 1 ; BNE LR14 CR1 tap_block{% endif %}{% endif %} ;;
{% if dual %}
    {{ mac('LR2') }} ; INC LR2 1 {% if fetch %}; {{ next_input() }}{% endif %}{% if repeat %}; DEC LR14 1 ; BNE LR14 CR1 tap_block{% endif %} ;;
{% endif %}
{% endfor %}
{% if separate and taps <= fix %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ;;
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
    SET LR12 {{ cr.in0_d0 }} ;;
batch:
{% if long %}
    {{ sum_direct() }}
    SET LR3 CR0 ;;
    INC LR3 125 ;;
{% endif %}
    SET LR8 {{ cr.n }} ; SUB LR9 LR0 CR1 ;;
feature:
    SET LR10 LR11 ; SET LR13 LR4 {% if wide_tail %}; SET LR3 {{ cr.dot_tail }}{% endif %} ;;
pixel:
    SET LR7 LR9 ; SET LR6 LR10 ; SET LR14 {{ cr.blocks }} ;;
    {{ seed() }}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% if long and not wide_tail %}
tap_block:
    {{ long_block('body') }}
    {{ long_block('final', true) }}
{% elif k > 32 %}
tap_block:
    {{ block(32) }}
{% endif %}
{% if not long or wide_tail %}
    {{ block((k-1)%32+1, true) }}
{% endif %}
{% if wide_tail %}
    BEQ LR3 CR1 width_tail ;;
{% endif %}
    {{ out('LR5', cr.active) }} {% if wide_tail %}; DEC LR3 1{% endif %} ;;
{% if wide_tail %}
    B advance ;;
width_tail:
    {{ out('LR5', cr.tail) }} ; SET LR3 {{ cr.dot_tail }} ;;
advance:
{% endif %}
    INC LR5 1 ; INC LR10 1 ; DEC LR13 1 ; BNE LR13 CR1 pixel ;;
    SET LR9 LR7 ; DEC LR8 1 ; BNE LR8 CR1 feature ;;
    ADD LR11 LR11 LR15 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
{% else %}
{# Transpose a half-width plane once; reuse each weight row for 64 dots. #}
{% set chunks = (k+127)//128 %}
{% macro pair_copy() %}MULT.VE LR4 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 6{% endmacro %}
{% macro gather(chunk, pairs) %}
    SET LR2 CR0 ; SET LR3 {{ cr.blocks }} ; SET LR10 CR0 ;;
    LD.MULT R0 LR8 {{ cr.panel }} {% if pairs > 2 %}; INC LR10 {{ pairs-2 }}{% endif %} ;;
{% if pairs > 1 %}
    {{ pair_copy() }} ; INC LR8 1 ; LD.MULT R0 LR8 {{ cr.panel }} ;;
{% if pairs > 2 %}
gather_{{ chunk }}:
    {{ pair_copy() }} ; INC LR8 1 ; DEC LR10 1 ; ADDBI LRD2 2 ; LD.MULT R0 LR8 {{ cr.panel }} ; BNE LR10 CR1 gather_{{ chunk }} ;;
{% endif %}
{% endif %}
    {{ pair_copy() }} ; INC LR8 1 {% if pairs > 1 %}; ADDBI LRD2 2{% endif %} ;;
    INC LR12 1 ; {{ aq(cr.panel,'LR12',cr.dot_tail if chunk == chunks-1 else cr.full,cr.qf_in0) }} ;;
{% endmacro %}
{% macro dot(tag) %}
    {{ coeff() }} ; SET LR10 LR12 ; SUB LR2 LR0 CR1 ;;
    LD.MULT R0 LR10 {{ cr.panel }} ; SET LR3 LR13 ;;
dot_{{ tag }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ cr.full }}.L ; INC LR10 {{ chunks }} ; INC LR2 1 ; DEC LR3 1 ; LD.MULT R0 LR10 {{ cr.panel }} ; BNE LR3 CR1 dot_{{ tag }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ cr.full }}.L ; INC LR2 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR11 CR0 ; SET LR6 CR0 ;;
    SET LR14 {{ cr.in0_d0 }} ;;
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
    MULT.VE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1 ; {{ aq(cr.panel,'LR9',cr.full,cr.qf_in0) }} ; DEC LR10 1 ; BNE LR10 CR1 pack_pair ;;
    SET LR1 {{ cr.second }} ; SET LR12 CR0 ; SET LR7 CR0 ;;
    SET LR4 CR0 ; INC LR7 64 ; DEC LR12 1 ;;
gather_pixel:
    SET LR8 LR5 ;;
{% for chunk in range(chunks) %}
    {{ gather(chunk, [64,k//2-64*chunk] | min) }}
{% endfor %}
    ADDBI LRD0 1 ; DEC LR7 1 ; BNE LR7 CR1 gather_pixel ;;
    SET LR0 CR0 ; SET LR9 {{ cr.n }} ; SET LR13 CR0 ;;
    SUB LR7 LR0 CR1 ;;
    INC LR13 63 ; DEC LR6 1 ;;
tiny_feature:
    {{ seed() }}
{% for chunk in range(chunks) %}
    SET LR12 CR0 ;;
{% if chunk %}
    INC LR12 {{ chunk }} ;;
{% endif %}
    {{ dot('high_' ~ chunk) }}
{% if chunk == (chunks-1 if not bias else (2 if chunks >= 3 else 0)) %}
    {{ dot('low_' ~ chunk) }}
{% endif %}
{% endfor %}
    INC LR6 1 ; {{ out('LR6', cr.active) }} ; DEC LR9 1 ; BNE LR9 CR1 tiny_feature ;;
    INC LR6 1 ;;
    ADD LR11 LR11 LR15 ; DEC LR14 1 ; BNE LR14 CR1 tiny_batch ;;
    HALT ;;
{% endif %}
