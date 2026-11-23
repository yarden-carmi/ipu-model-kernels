{% set tiny = in0_d2 * in0_d3 == 64 and k % 2 == 0 and n % 2 == 0 and 128 % in0_d3 == 0 and in0_d0 == 1 %}
{% set w = cr.w if bias else cr.w_unbiased %}
{% macro mac(scalar, first=false) %}MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro aq(base, row, ds, q, act='identity') %}ACTIVATE.QUANTIZE {{ act }} {{ ds }}.L {{ q }}.L {{ base }} {{ row }}{% endmacro %}
{% macro copy8(q) %}MULT.VE LR4 CR1 0 LR4 {{ cr.full }}.L {{ q }}.L ; ACC.RESHAPE LRD0 LRD2 6{% endmacro %}
{% if not tiny %}
{% set c = [1, 128 // in0_d3] | max %}
{% set p = (c if in0_d2 % c == 0 or (in0_d2 * in0_d3 == 64 and 128 % in0_d3 == 0) else 1) - (1 if in0_d3 == 32 and in0_d2 % 4 == 0 and k <= 96 else 0) %}
{% set pitch = ((in0_d2 + p - 1) // p) * ((p * in0_d3 + 127) // 128) %}
{% set spatial = in0_d2 * in0_d3 %}
{% set middle = k >= 256 and spatial > 1024 %}
{% set fix = 26 if middle else (16 if p == 3 and not bias else (22 if spatial <= 256 else ((25 if spatial > 1024 else 24) if k >= 256 else (26 if k >= 128 else 32)))) %}
{% macro corrected(j) %}{{ j < 12 or j >= 18 if middle else j < fix }}{% endmacro %}
{% macro next_input() %}ADD LR6 LR6 LR4 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endmacro %}
{% macro block(taps, tag) %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ; SET LR1 CR0 ; SET LR2 {{ cr.lanes128 }} ;;
    INC LR7 1 ; LD.MULT R1 LR7 {{ w }} ; DEC LR1 1 ; DEC LR2 1 ;;
{% if middle %}
{% for j in range(taps) %}
{% set dual = corrected(j) == 'True' %}
    {{ mac('LR1') }} ; INC LR1 1 {% if not dual %}; INC LR2 1 ; {{ next_input() }}{% endif %} ;;
{% if dual %}
    {{ mac('LR2') }} ; INC LR2 1 ; {{ next_input() }} {% if j+1 == taps %}; DEC LR14 1 ; BNE LR14 CR1 block_loop{% endif %} ;;
{% endif %}
{% endfor %}
{% else %}
{% if fix %}{{ tag }}_dual:
    {{ mac('LR1') }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; INC LR2 1 ; {{ next_input() }} ; BLT.S LR1 LR3 {{ tag }}_dual ;;
{% endif %}
{% for j in range(fix, taps) %}
    {{ mac('LR1') }} ; INC LR1 1 ; {{ next_input() }} ;;
{% endfor %}
    DEC LR14 1 ; BNE LR14 CR1 block_loop ;;
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
    SET LR11 CR0 ; INC LR12 {{ in0_d0 }} ; SET LR3 CR0 ;;
    INC LR3 {{ [0, fix - 1] | max }} ;;
batch:
    SET LR8 {{ cr.n }} ; SET LR9 CR0 ;;
    DEC LR9 1 ;;
feature:
    SET LR10 LR11 ; SET LR13 LR4 ;;
pixel:
    SET LR7 LR9 ; SET LR6 LR10 ; SET LR14 CR0 ;;
    INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ w }} LR0 ; INC LR14 {{ (k-1) // 32 }} ;;
    {{ mac('CR1', true) }} ; INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ w }} LR0 ;;
    {{ mac('CR1') }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% if k > 32 %}
block_loop:
    {{ block(32, 'full') }}
{% endif %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ; SET LR1 CR0 ; SET LR2 {{ cr.lanes128 }} ;;
    INC LR7 1 ; LD.MULT R1 LR7 {{ w }} ; DEC LR1 1 ; DEC LR2 1 ;;
{% set last = (k-1)%32+1 %}
{% for j in range(last) %}
{% set dual = corrected(j) == 'True' %}
    {{ mac('LR1') }} ; INC LR1 1 {% if not dual %}; INC LR2 1 {% if j+1 < last %}; {{ next_input() }}{% endif %}{% endif %} ;;
{% if dual %}
    {{ mac('LR2') }} ; INC LR2 1 {% if j+1 < last %}; {{ next_input() }}{% endif %} ;;
{% endif %}
{% endfor %}
{% if p == 3 and in0_d2 % 3 and in0_d3 == 32 %}
    BEQ LR13 CR1 partial_store ;;
{% endif %}
    {{ aq(cr.out0, 'LR5', cr.full if p * in0_d3 >= 128 else cr.active, cr.qf_out0, act_out0 | default('identity')) }} ;;
    INC LR5 1 ; INC LR10 1 ; DEC LR13 1 ; BNE LR13 CR1 pixel ;;
{% if p == 3 and in0_d2 % 3 and in0_d3 == 32 %}
    B next_feature ;;
partial_store:
    {{ aq(cr.out0, 'LR5', cr.spatial_tail, cr.qf_out0, act_out0 | default('identity')) }} ;;
    INC LR5 1 ;;
next_feature:
{% endif %}
    SET LR9 LR7 ; DEC LR8 1 ; BNE LR8 CR1 feature ;;
    ADD LR11 LR11 LR15 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
{% else %}
{# For a half-full spatial row, gather a K-major dot panel once. Each
   weight chunk then stays resident while AGG fills the spatial output. #}
{% macro weight(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w if bias else cr.w_unbiased }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro bias_mac(slot, mode) %}MULT.RC.VE {{ slot }} CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{% macro reduce(slot, dest) %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM {{ dest }} {{ cr.full }}.L{% endmacro %}

    {# Transpose pairs of channels from the packed 64-pixel rows. #}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR7 CR0 ;;
    INC LR3 64 ; SET LR9 LR5 ;;
{% for j in range((k//2 + 127)//128) %}
    INC LR7 {{ [128, k//2 - 128*j] | min }} ;;
{% endfor %}
    SET LR8 CR0 ; DEC LR9 1 ;;
pack_pair:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    INC LR8 1 ; LD.MULT R1 LR8 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR8 1 ;;
    MULT.VE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1 ; DEC LR7 1 ; {{ aq(cr.panel, 'LR9', cr.full, cr.qf_in0) }} ; BNE LR7 CR1 pack_pair ;;
    SET LR4 CR0 ; SET LR13 LR5 ; SET LR5 CR0 ;;
    SET LR0 CR0 ; SET LR1 LR6 ; INC LR7 64 ;;
    SET LR11 CR1 ;;
    INC LR11 1 ;;
gather_pixel:
    SET LR8 LR13 ; SET LR9 {{ cr.chunks }} ;;
gather_chunk:
    SET LR2 CR0 ; SET LR3 LR14 ; SET LR10 CR0 ;;
    INC LR10 {{ 64 if k % 128 == 0 else k % 128 // 2 }} ;;
{% if k > 128 and k % 128 %}
    BEQ LR9 CR1 gather_start ;;
    SET LR10 CR0 ;;
    INC LR10 64 ;;
{% endif %}
gather_start:
    LD.MULT R0 LR8 {{ cr.panel }} ;;
    DEC LR10 1 ; {{ copy8(cr.qf_in0) }} ; BEQ LR10 CR1 gather_single ;;
    INC LR8 1 ; LD.MULT R0 LR8 {{ cr.panel }} ; BEQ LR10 CR1 gather_last ;;
gather_pair:
    ADDBI LRD2 2 ; DEC LR10 1 ; INC LR8 1 ; {{ copy8(cr.qf_in0) }} ; LD.MULT R0 LR8 {{ cr.panel }} ; BNE LR10 LR11 gather_pair ;;
gather_last:
    ADDBI LRD2 2 ; {{ copy8(cr.qf_in0) }} ;;
gather_single:
    INC LR8 1 ;;
gather_store:
    {% if k > 128 %}BEQ LR9 CR1 gather_tail ;;
    {{ aq(cr.panel, 'LR5', cr.full, cr.qf_in0) }} ;;
    INC LR5 1 ; DEC LR9 1 ; B gather_chunk ;;
gather_tail:
    {% endif %}{{ aq(cr.panel, 'LR5', cr.active, cr.qf_in0) }} ;;
    ADDBI LRD0 1 ; DEC LR7 1 ; INC LR5 1 ; BNE LR7 CR1 gather_pixel ;;
    SET LR0 CR0 ; SET LR1 {{ cr.lanes128 }} ; SET LR8 CR0 ;;
    SET LR4 CR0 ; SET LR6 CR0 ; SET LR13 CR0 ;;
{% for j in range((n+127)//128) %}
    INC LR13 {{ [128,n-128*j] | min }} ;;
{% endfor %}
    DEC LR4 1 ;;
tiny_feature:
    {{ weight('LR0') }} ;;
    {{ bias_mac('LR0','ADD.FIRST') }} ; {{ weight('LR0') }} ; SET LR7 {{ cr.chunks }} ;;
    {{ bias_mac('LR0','ADD') }} ; SET LR8 CR0 ; SET LR12 CR0 ;;
{% if k >= 384 %}
    INC LR8 2 ;;
{% endif %}
    {{ weight('LR0') }} ; SET LR11 CR1 ;;
    INC LR11 1 ;;
tiny_chunk:
    SET LR10 LR8 ; SET LR3 CR0 ; SET LR9 CR0 ;;
    LD.MULT R0 LR10 {{ cr.panel }} ; INC LR9 63 ; DEC LR3 1 ;;
tiny_pixel:
    {{ reduce('LR0','LR3') }} ; ADD LR10 LR10 {{ cr.chunks }} ; INC LR3 1 ; DEC LR9 1 ; LD.MULT R0 LR10 {{ cr.panel }} ; BNE LR9 CR1 tiny_pixel ;;
    {{ reduce('LR0','LR3') }} ; INC LR3 1 ; BEQ LR12 CR0 tiny_correction ;;
    DEC LR7 1 ; BEQ LR7 CR1 tiny_store ;;
{% if k >= 384 %}
    INC LR8 1 ; {{ weight('LR0') }} ;;
    BNE LR8 {{ cr.chunks }} tiny_chunk ;;
    SET LR8 CR0 ;;
    B tiny_chunk ;;
{% else %}
    INC LR8 1 ; {{ weight('LR0') }} ; B tiny_chunk ;;
{% endif %}
tiny_correction:
    {{ weight('LR0') }} ; INC LR12 1 ; B tiny_chunk ;;
tiny_store:
    {{ aq(cr.out0, 'LR6', cr.half, cr.qf_out0, act_out0 | default('identity')) }} ;;
    INC LR6 1 ; DEC LR13 1 ; BNE LR13 CR1 tiny_feature ;;
    HALT ;;
{% endif %}
