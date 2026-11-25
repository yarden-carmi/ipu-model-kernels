{% set w = cr.w if bias else cr.w_unbiased %}
{% set spatial = in0_d2 * in0_d3 %}
{% set tiny = spatial == 64 and k % 2 == 0 and 128 % in0_d3 == 0 and in0_d0 == 1 %}
{% macro mac(vector, scalar, first=false) %}MULT.RC.VE {{ vector }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro aq(base, row, ds, q, act='identity') %}ACTIVATE.QUANTIZE {{ act }} {{ ds }}.L {{ q }}.L {{ base }} {{ row }}{% endmacro %}
{% macro out(row, ds) %}{{ aq(cr.out0, row, ds, cr.qf_out0, act_out0 | default('identity')) }}{% endmacro %}
{% macro clear() %}MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST{% endmacro %}
{% if not tiny %}
{# Keep the coefficient pair resident and pipeline each next spatial load. #}
{% set fix = (24 if bias else 32) if spatial > 256 else 22 %}
{% set middle = k >= 256 and spatial > 1024 %}
{% set group = 96 if middle else 32 %}
{% set p = [1, 128 // in0_d3] | max %}
{% if in0_d2 % p and not (spatial == 64 and 128 % in0_d3 == 0) %}{% set p = 1 %}{% endif %}
{% macro advance_input() %}ADD LR6 LR6 LR4 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endmacro %}
{% macro backedge() %}DEC LR14 1 ; BNE LR14 CR1 block_loop{% endmacro %}
{% set fused_store = middle and (in0_d3 <= 128 or in0_d3 % 128 == 0) %}
{% set row_ds = cr.last_lanes if [in0_d2, p] | min * in0_d3 < 128 else cr.full %}
{% macro block(taps, last=false) %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ; SET LR1 CR0 ; SET LR2 {{ cr.lanes128 }} ;;
    INC LR7 1 ; LD.MULT R1 LR7 {{ w }} ; DEC LR1 1 ; DEC LR2 1 ;;
{% macro taps_body(taps, start, last, end) %}
{% for j in range(start, start+taps) %}
{% set dual = j % 8 != 3 if middle else j < fix %}
{% set final_tap = end and loop.last %}
{% set advance = not last or not final_tap %}
    {{ mac('LR0','LR1') }} ; INC LR1 1 {% if not dual and advance %}; {{ advance_input() }}{% if middle and not final_tap %} ; INC LR2 1{% endif %}{% endif %}{% if not last and final_tap and not dual %} ; {{ backedge() }}{% endif %} ;;
{% if dual %}
    {{ mac('LR0','LR2') }} ; INC LR2 1 {% if advance %}; {{ advance_input() }}{% endif %}{% if not last and final_tap %} ; {{ backedge() }}{% endif %} ;;
{% endif %}
{% endfor %}
{% endmacro %}
    {{ taps_body([32, taps] | min, 0, last, taps <= 32) }}
{% if taps > 32 %}
    {{ taps_body([32, taps-32] | min, 32, last, taps <= 64) }}
{% endif %}
{% if taps > 64 %}
    {{ taps_body(taps-64, 64, last, true) }}
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
    SET LR12 {{ cr.in0_d0 }} {% if fused_store %}; DEC LR5 1{% endif %} ;;
{% if fused_store and bias %}
    SET LR3 CR0 ;;
    INC LR3 {{ (k-1)//group }} ;;
{% endif %}
batch:
    SET LR8 {{ cr.n }} ; SET LR9 CR0 ;;
    DEC LR9 1 ;;
feature:
    SET LR10 LR11 ; SET LR13 LR4 ;;
{% if in0_d3 > 128 and in0_d3 % 128 %}
reset_scanline:
    SET LR3 {{ cr.inner }} ;;
{% endif %}
pixel:
{% if fused_store and bias %}
    ADD LR7 LR9 CR1 ; SET LR6 LR10 ; SET LR14 LR3 ; LD.MULT.CYCLIC LR7 {{ w }} LR0 ;;
    {{ mac('LR0','CR1',true) }} ; INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ w }} LR0 ;;
    {{ mac('LR0','CR1') }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% else %}
    SET LR7 LR9 ; SET LR6 LR10 ; SET LR14 CR0 ;;
{% if bias %}
    INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ w }} LR0 ; INC LR14 {{ (k-1)//group }} ;;
    {{ mac('LR0','CR1',true) }} ; INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ w }} LR0 ;;
    {{ mac('LR0','CR1') }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% else %}
    {{ clear() }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; INC LR14 {{ (k-1)//group }} ;;
{% endif %}
{% endif %}
{% if k > group %}
block_loop:
    {{ block(group) }}
{% endif %}
    {{ block((k-1)%group+1, true) }}
{% if in0_d3 > 128 and in0_d3 % 128 %}
    DEC LR3 1 ; BEQ LR3 CR1 partial ;;
{% endif %}
{% if fused_store %}
    {{ out('LR5', row_ds) }} ; INC LR5 1 ; INC LR10 1 ; DEC LR13 1 ; BNE LR13 CR1 pixel ;;
{% else %}
    {{ out('LR5', row_ds) }} ;;
    INC LR5 1 ; INC LR10 1 ; DEC LR13 1 ; BNE LR13 CR1 pixel ;;
{% endif %}
{% if in0_d3 > 128 and in0_d3 % 128 %}
    B next_feature ;;
partial:
    {{ out('LR5', cr.last_lanes) }} ; INC LR5 1 ; INC LR10 1 ; DEC LR13 1 ; BNE LR13 CR1 reset_scanline ;;
next_feature:
{% endif %}
    SET LR9 LR7 ; DEC LR8 1 ; BNE LR8 CR1 feature ;;
    ADD LR11 LR11 LR15 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
{% else %}
{# Half-row images: transpose pairs once, then reuse coefficients across pixels. #}
{% macro weight() %}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0{% endmacro %}
{% macro copy_pair() %}MULT.VE LR4 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 6{% endmacro %}
{% macro reduce() %}MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR7 CR0 ;;
    INC LR3 64 ; SET LR9 LR5 ;;
{% for j in range((k//2 + 127)//128) %}
    INC LR7 {{ [128, k//2 - j*128] | min }} ;;
{% endfor %}
    SET LR8 CR0 ; DEC LR9 1 ;;
pack_pair:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    INC LR8 1 ; LD.MULT R1 LR8 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR8 1 ;;
    MULT.VE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1 ; DEC LR7 1 ; {{ aq(cr.panel,'LR9',cr.full,cr.qf_in0) }} ; BNE LR7 CR1 pack_pair ;;
    SET LR4 CR0 ; SET LR13 LR5 ; SET LR5 CR0 ;;
    SET LR1 LR6 ; INC LR7 64 ; SET LR11 CR1 ;;
    INC LR11 1 ;;
gather_pixel:
    SET LR8 LR13 ; SET LR9 {{ cr.inner }} ;;
gather_chunk:
    SET LR2 CR0 ; SET LR3 LR14 ; SET LR10 CR0 ;;
    INC LR10 {{ ((k-1)%128+1)//2 }} ;;
{% if k > 128 and k % 128 %}
    BEQ LR9 CR1 gather_start ;;
    SET LR10 CR0 ;;
    INC LR10 64 ;;
{% endif %}
gather_start:
    LD.MULT R0 LR8 {{ cr.panel }} ;;
    DEC LR10 1 ; {{ copy_pair() }} ; BEQ LR10 CR1 gather_single ;;
    INC LR8 1 ; LD.MULT R0 LR8 {{ cr.panel }} ; BEQ LR10 CR1 gather_last ;;
gather_pair:
    ADDBI LRD2 2 ; DEC LR10 1 ; INC LR8 1 ; {{ copy_pair() }} ; LD.MULT R0 LR8 {{ cr.panel }} ; BNE LR10 LR11 gather_pair ;;
gather_last:
    ADDBI LRD2 2 ; {{ copy_pair() }} ;;
gather_single:
    INC LR8 1 ;;
{% if k > 128 %}
    BEQ LR9 CR1 gather_tail ;;
    {{ aq(cr.panel,'LR5',cr.full,cr.qf_in0) }} ;;
    INC LR5 1 ; DEC LR9 1 ; B gather_chunk ;;
gather_tail:
{% endif %}
    {{ aq(cr.panel,'LR5',cr.active,cr.qf_in0) }} ;;
    ADDBI LRD0 1 ; DEC LR7 1 ; INC LR5 1 ; BNE LR7 CR1 gather_pixel ;;
    SET LR0 CR0 ; SET LR4 CR0 ; SET LR6 CR0 ;;
    DEC LR4 1 ; SET LR13 {{ cr.n }} ;;
tiny_feature:
    {{ weight() }} ; SET LR7 {{ cr.inner }} ; SET LR12 CR0 ;;
{% if bias %}
    {{ mac('LR0','CR1',true) }} ; {{ weight() }} ;;
    {{ mac('LR0','CR1') }} ; {{ weight() }} ;;
{% else %}
    {{ clear() }} ;;
{% endif %}
    SET LR8 CR0 ;;
{% if k >= 384 %}
    INC LR8 2 ;;
{% endif %}
tiny_chunk:
    SET LR10 LR8 ; SET LR3 CR0 ; SET LR9 CR0 ;;
    LD.MULT R0 LR10 {{ cr.panel }} ; INC LR9 63 ; DEC LR3 1 ;;
tiny_pixel:
    {{ reduce() }} ; ADD LR10 LR10 {{ cr.inner }} ; INC LR3 1 ; DEC LR9 1 ; LD.MULT R0 LR10 {{ cr.panel }} ; BNE LR9 CR1 tiny_pixel ;;
    {{ reduce() }} ; INC LR3 1 ; BEQ LR12 CR0 correction ;;
    DEC LR7 1 ; BEQ LR7 CR1 tiny_store ;;
    INC LR8 1 ; {{ weight() }} ;;
{% if k >= 384 %}
    BNE LR8 {{ cr.inner }} tiny_chunk ;;
    SET LR8 CR0 ;;
{% endif %}
    B tiny_chunk ;;
correction:
    {{ weight() }} ; INC LR12 1 ; B tiny_chunk ;;
tiny_store:
    {{ out('LR6',cr.half) }} ;;
    INC LR6 1 ; DEC LR13 1 ; BNE LR13 CR1 tiny_feature ;;
    HALT ;;
{% endif %}
