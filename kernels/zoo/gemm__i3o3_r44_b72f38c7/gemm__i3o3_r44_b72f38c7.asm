{% set tiny = in0_d2 * in0_d3 == 64 and in0_d0 == 1 and k % 2 == 0 %}
{% set spatial = in0_d2 * in0_d3 %}
{% set w = cr.w if bias else cr.w_unbiased %}
{% macro mac(s, first=false) %}MULT.RC.VE LR0 {{ s }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro aq(base, row, ds, q, act='identity') %}ACTIVATE.QUANTIZE {{ act }} {{ ds }}.L {{ q }}.L {{ base }} {{ row }}{% endmacro %}
{% if not tiny %}
{# Each lane is a spatial point. Stream inputs one ahead and hold 32
   scalar coefficients and their optional residuals in R0/R1. #}
{% set pack3 = in0_d3 == 32 and in0_d2 % 4 == 0 and k <= 96 %}
{% set fix = 27 if spatial > 1024 and k > 128 else (25 if (spatial > 1024 and k > 64) or (in0_d3 == 32 and k >= 128) else (16 if pack3 else (23 if spatial > 1024 or (spatial >= 256 and k >= 128) else 32))) %}
{% macro next_input() %}ADD LR6 LR6 LR4 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endmacro %}
{% macro block(taps, last=false) %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ; SUB LR1 LR0 CR1 ; SUB LR2 LR15 CR1 ;;
{% for j in range(taps) %}
{% set dual = (j < 12 or j >= 12 + 32 - fix) if fix >= 25 else (j < fix) %}
    {{ mac('LR1') }} ; INC LR1 1 {% if loop.first %}; INC LR7 1 ; LD.MULT R1 LR7 {{ w }} {% endif %}{% if not dual %} ; INC LR2 1 {% if not (last and loop.last) %}; {{ next_input() }}{% endif %}{% endif %} ;;
{% if not dual and loop.last and not last %}
    DEC LR14 1 ; BNE LR14 CR1 block_loop ;;
{% endif %}
{% if dual %}
    {{ mac('LR2') }} ; INC LR2 1 {% if not (last and loop.last) %}; {{ next_input() }}{% endif %} {% if loop.last and not last %}; DEC LR14 1 ; BNE LR14 CR1 block_loop{% endif %} ;;
{% endif %}
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ;;
    SET LR11 CR0 ; SET LR15 {{ cr.lanes128 }} ;;
batch:
    SET LR8 {{ cr.n }} ; SUB LR9 LR0 CR1 ;;
feature:
    SET LR10 LR11 ; SET LR13 LR4 ;;
{% if in0_d3 > 128 and in0_d3 % 128 %}
    SET LR3 {{ cr.half_or_width }} ;;
{% endif %}
pixel:
    SET LR7 LR9 ; SET LR6 LR10 ; SET LR14 {{ cr.blocks_before_tail }} ;;
    INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ w }} LR0 ;;
    {{ mac('CR1', true) }} ; INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ w }} LR0 ;;
    {{ mac('CR1') }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% if k > 32 %}
block_loop:
    {{ block(32) }}
{% endif %}
    {{ block((k-1)%32+1, true) }}
{% if in0_d3 > 128 and in0_d3 % 128 %}
    BEQ LR3 CR1 width_tail ; DEC LR3 1 ;;
    {{ aq(cr.out0, 'LR5', cr.full, cr.qf_out0, act_out0 | default('identity')) }} ; B advance_pixel ;;
width_tail:
    {{ aq(cr.out0, 'LR5', cr.chunk_or_tail, cr.qf_out0, act_out0 | default('identity')) }} ; SET LR3 {{ cr.half_or_width }} ;;
advance_pixel:
{% else %}
{% if pack3 and in0_d2 % 3 %}
    BEQ LR13 CR1 partial_store ;;
{% endif %}
    {{ aq(cr.out0, 'LR5', cr.active, cr.qf_out0, act_out0 | default('identity')) }} ;;
{% endif %}
    INC LR5 1 ; INC LR10 1 ; DEC LR13 1 ; BNE LR13 CR1 pixel ;;
{% if pack3 and in0_d2 % 3 %}
    B next_feature ;;
partial_store:
    {{ aq(cr.out0, 'LR5', cr.chunk_or_tail, cr.qf_out0, act_out0 | default('identity')) }} ;;
    INC LR5 1 ;;
next_feature:
{% endif %}
    SET LR9 LR7 ; DEC LR8 1 ; BNE LR8 CR1 feature ;;
    ADD LR11 LR11 {{ cr.batch_pitch }} ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
{% else %}
{# At 64 spatial points, transpose a dot panel once. Dot reductions
   then fill spatial output lanes without half-width MACs in the hot loop. #}
{% macro copy_pair() %}MULT.VE LR4 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 6{% endmacro %}
{% macro weight() %}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0{% endmacro %}
{% macro reduce() %}MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR9 LR5 ;;
    INC LR3 64 ; DEC LR9 1 ; SET LR8 CR0 ;;
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
    SET LR8 LR13 ; SET LR9 {{ cr.chunk_or_tail }} ;;
gather_chunk:
    SET LR2 CR0 ; SET LR3 LR14 ; SET LR10 CR0 ;;
    INC LR10 {{ (k-1)%128//2+1 }} ;;
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
    {{ aq(cr.panel, 'LR5', cr.full, cr.qf_in0) }} ;;
    INC LR5 1 ; DEC LR9 1 ; B gather_chunk ;;
gather_tail:
{% endif %}
    {{ aq(cr.panel, 'LR5', cr.active, cr.qf_in0) }} ;;
    ADDBI LRD0 1 ; DEC LR7 1 ; INC LR5 1 ; BNE LR7 CR1 gather_pixel ;;
    SET LR0 CR0 ; SET LR6 CR0 ; SET LR13 {{ cr.n }} ;;
    SUB LR4 LR0 CR1 ;;
tiny_feature:
    {{ weight() }} ;;
    {{ mac('CR1', true) }} ; {{ weight() }} ; SET LR7 {{ cr.chunk_or_tail }} ;;
    {{ mac('CR1') }} ; SET LR8 CR0 ; SET LR12 CR0 ;;
{% if k >= 384 %}
    INC LR8 2 ;;
{% endif %}
    {{ weight() }} ;;
tiny_chunk:
    SET LR10 LR8 ; SUB LR3 LR0 CR1 ; SET LR9 CR0 ;;
    LD.MULT R0 LR10 {{ cr.panel }} ; INC LR9 63 ;;
tiny_pixel:
    {{ reduce() }} ; ADD LR10 LR10 {{ cr.chunk_or_tail }} ; INC LR3 1 ; DEC LR9 1 ; LD.MULT R0 LR10 {{ cr.panel }} ; BNE LR9 CR1 tiny_pixel ;;
    {{ reduce() }} ; INC LR3 1 ; BEQ LR12 CR0 tiny_correction ;;
    DEC LR7 1 ; BEQ LR7 CR1 tiny_store ;;
    INC LR8 1 ; {{ weight() }} ;;
    BNE LR8 {{ cr.chunk_or_tail }} tiny_chunk ;;
    SET LR8 CR0 ; B tiny_chunk ;;
tiny_correction:
    {{ weight() }} ; INC LR12 1 ; B tiny_chunk ;;
tiny_store:
    {{ aq(cr.out0, 'LR6', cr.half_or_width, cr.qf_out0, act_out0 | default('identity')) }} ;;
    INC LR6 1 ; DEC LR13 1 ; BNE LR13 CR1 tiny_feature ;;
    HALT ;;
{% endif %}
