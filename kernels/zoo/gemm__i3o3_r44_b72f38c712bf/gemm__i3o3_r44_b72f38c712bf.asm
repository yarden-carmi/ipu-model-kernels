{% set spatial = in0_d2 * in0_d3 %}
{% set tiny = spatial == 64 and k % 2 == 0 and 128 % in0_d3 == 0 and in0_d0 == 1 %}
{% set w = cr.w if bias else cr.w_unbiased %}
{% macro aq(base, row, ds, q, act='identity') %}ACTIVATE.QUANTIZE {{ act }} {{ ds }}.L {{ q }}.L {{ base }} {{ row }}{% endmacro %}
{% macro mac(scalar, first=false) %}MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro out(row, ds) %}{{ aq(cr.out0,row,ds,cr.qf_out0,act_out0 | default('identity')) }}{% endmacro %}
{% if not tiny %}
{# A broadcast coefficient updates a full spatial row. Stream the high
   and residual coefficient vectors into the two multiplier banks. #}
{% set pack3 = in0_d3 == 32 and in0_d2 % 4 == 0 and k <= 96 %}
{% set stride = (in0_d3+127)//128 %}
{% set pipelined = k >= 256 and spatial > 1024 %}
{% set fused = pipelined and k % 32 == 0 and in0_d3 <= 128 %}
{% set fix = 16 if pack3 and not bias else (22 if spatial <= 256 or k <= 64 else ((26 if spatial > 1024 else 24) if k >= 256 else 26)) %}
{% macro next_input() %}ADD LR6 LR6 LR4 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endmacro %}
{% macro block(taps, last=false, alternate=false) %}
{% if not pipelined %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ;;
{% endif %}
    INC LR7 1 ; LD.MULT R1 LR7 {{ w }} ; SUB LR1 LR0 CR1 ; SET LR2 {{ cr.scalar127 }} ;;
{% for j in range(taps) %}
{% set dual = (j not in ([14,15,16,17] if alternate else [27,28,29,30]) and not (last and j == 26)) if pipelined else j < fix %}
{% set more = not last or not loop.last %}
    {{ mac('LR1') }} ; INC LR1 1 {% if fused and last and loop.last %}; INC LR10 1 {% endif %}{% if pipelined and not last and loop.last and dual %}; INC LR7 1 ; LD.MULT R0 LR7 {{ w }}{% endif %}{% if not dual %}; INC LR2 1 {% if more %}; {{ next_input() }}{% endif %}{% endif %} ;;
{% if dual %}
    {{ mac('LR2') }} ; INC LR2 1 {% if more %}; {{ next_input() }}{% endif %}{% if pipelined and loop.last and not last %}; DEC LR14 1 {% if alternate %}; BNE LR14 CR1 block_loop{% endif %}{% endif %}{% if fused and last and loop.last %}; {{ out('LR5',cr.active) }} ; INC LR5 1 ; DEC LR13 1 ; BNE LR13 CR1 pixel{% endif %} ;;
{% endif %}
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
{% if fused %}    DEC LR5 1 ;;
{% endif %}
batch:
    SET LR8 {{ cr.n }} ; SET LR9 CR0 ;;
feature:
    SET LR10 LR11 ; SET LR13 LR4 ;;
{% if stride > 1 %}
    SET LR3 {{ cr.width_rows }} ;;
{% endif %}
pixel:
    SET LR7 LR9 ; SET LR6 LR10 ; SET LR14 {{ cr.loop_count }} ; LD.MULT.CYCLIC LR9 {{ w }} LR0 ;;
    {{ mac('CR1', true) }} ; INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ w }} LR0 ;;
    {{ mac('CR1') }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% if pipelined %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ;;
{% endif %}
{% if k > 32 %}
{% if pipelined and ((k-1)//32)%2 %}
    {{ block(32) }}
{% endif %}
block_loop:
    {{ block(32) }}
{% if pipelined %}
    {{ block(32, false, true) }}
{% endif %}
{% if not pipelined %}
    DEC LR14 1 ; BNE LR14 CR1 block_loop ;;
{% endif %}
{% endif %}
    {{ block((k-1)%32+1, true) }}
{% if not fused %}
{% if pack3 and in0_d2 % 3 %}
    BEQ LR13 CR1 partial_store ;;
{% endif %}
{% if stride > 1 and in0_d3 % 128 %}
    BEQ LR3 CR1 tail_store ;;
{% endif %}
    {{ out('LR5',cr.active) }} ;;
{% if stride > 1 and in0_d3 % 128 %}
    DEC LR3 1 ; B advance ;;
tail_store:
    {{ out('LR5',cr.dot_tail) }} ; SET LR3 {{ cr.width_rows }} ;;
advance:
{% endif %}
    INC LR5 1 ; INC LR10 1 ; DEC LR13 1 ; BNE LR13 CR1 pixel ;;
{% if pack3 and in0_d2 % 3 %}
    B next_feature ;;
partial_store:
    {{ out('LR5',cr.dot_tail) }} ;;
    INC LR5 1 ;;
next_feature:
{% endif %}
{% endif %}
    SET LR9 LR7 ; DEC LR8 1 ;;
    INC LR9 1 ; BNE LR8 CR0 feature ;;
    ADD LR11 LR11 LR15 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
{% else %}
{# Half-width spatial planes: transpose once, then reduce full K vectors. #}
{% macro copy_pair() %}MULT.VE LR4 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 6{% endmacro %}
{% macro load_w() %}LD.MULT.CYCLIC LR4 {{ w }} LR0 ; INC LR4 1{% endmacro %}
{% macro reduce() %}MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ;;
    INC LR3 64 ; SET LR9 LR5 ; SET LR8 CR0 ;;
    DEC LR9 1 ;;
pack_pair:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    INC LR8 1 ; LD.MULT R1 LR8 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR8 1 ;;
    MULT.VE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1 ; DEC LR7 1 ; {{ aq(cr.panel,'LR9',cr.full,cr.qf_in0) }} ; BNE LR7 CR1 pack_pair ;;
    SET LR4 CR0 ; SET LR13 LR5 ; SET LR5 CR0 ;;
    SET LR0 CR0 ; SET LR1 LR6 ; INC LR7 64 ;;
    SET LR11 CR0 ;;
    INC LR11 2 ;;
gather_pixel:
    SET LR8 LR13 ; SET LR9 {{ cr.loop_count }} ;;
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
    {{ aq(cr.panel,'LR5',cr.full,cr.qf_in0) }} ;;
    INC LR5 1 ; DEC LR9 1 ; B gather_chunk ;;
gather_tail:
{% endif %}
    {{ aq(cr.panel,'LR5',cr.dot_tail,cr.qf_in0) }} ;;
    ADDBI LRD0 1 ; DEC LR7 1 ; INC LR5 1 ; BNE LR7 CR1 gather_pixel ;;
    SET LR0 CR0 ; SET LR4 CR0 ; SET LR6 CR0 ;;
    SET LR13 {{ cr.n }} ; DEC LR4 1 ;;
tiny_feature:
    {{ load_w() }} ;;
    {{ mac('CR1', true) }} ; {{ load_w() }} ;;
    {{ mac('CR1') }} ; SET LR8 CR0 ; SET LR12 CR0 ; SET LR7 {{ cr.loop_count }} ;;
{% if k >= 384 %}
    INC LR8 2 ;;
{% endif %}
    {{ load_w() }} ;;
tiny_chunk:
    SET LR10 LR8 ; SET LR3 CR0 ; SET LR9 CR0 ;;
    LD.MULT R0 LR10 {{ cr.panel }} ; INC LR9 63 ; DEC LR3 1 ;;
tiny_pixel:
    {{ reduce() }} ; ADD LR10 LR10 {{ cr.loop_count }} ; INC LR3 1 ; DEC LR9 1 ; LD.MULT R0 LR10 {{ cr.panel }} ; BNE LR9 CR1 tiny_pixel ;;
    {{ reduce() }} ; INC LR3 1 ; BEQ LR12 CR0 tiny_correction ;;
    DEC LR7 1 ; BEQ LR7 CR1 tiny_store ;;
    INC LR8 1 ; {{ load_w() }} ;;
{% if k >= 384 %}
    BNE LR8 {{ cr.loop_count }} tiny_chunk ;;
    SET LR8 CR0 ;;
{% endif %}
    B tiny_chunk ;;
tiny_correction:
    {{ load_w() }} ; INC LR12 1 ; B tiny_chunk ;;
tiny_store:
    {{ out('LR6',cr.half) }} ;;
    INC LR6 1 ; DEC LR13 1 ; BNE LR13 CR1 tiny_feature ;;
    HALT ;;
{% endif %}
