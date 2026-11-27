{% set spatial = in0_d2 * in0_d3 %}
{% set group = 96 if in0_d3 == 32 and in0_d2 % 4 == 0 and k <= 96 else (spatial if spatial < 128 else 128) %}
{% set tiny = spatial == 64 and k % 2 == 0 and 128 % in0_d3 == 0 and in0_d0 == 1 %}
{% set w = cr.w if bias else cr.w_unbiased %}
{% macro aq(base, row, ds, q, act='identity') %}ACTIVATE.QUANTIZE {{ act }} {{ ds }}.L {{ q }}.L {{ base }} {{ row }}{% endmacro %}
{% macro mac(scalar, first=false) %}MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro out(row, ds) %}{{ aq(cr.out0,row,ds,cr.qf_out0,act_out0 | default('identity')) }}{% endmacro %}
{% if k == 128 and spatial == 4096 and in0_d0 == 1 %}
    SET LR0 CR0 ; SET LR10 CR0 ; SET LR5 CR0 ;;
    SET LR13 {{ cr.n }} ; DEC LR5 1 ; SET LR8 CR0 ;;
new_feature:
    SET LR1 CR0 ; SET LR8 CR0 ; SET LR14 CR0 ;;
    INC LR8 32 ; INC LR14 61 ; SET LR2 CR0 ;;
    INC LR2 30 ; SET LR3 CR0 ; SET LR9 CR0 ;;
    INC LR3 29 ; INC LR9 25 ; SET LR6 CR0 ;;
    INC LR6 18 ; SET LR7 CR0 ;;
    INC LR7 16 ; SET LR4 CR0 ;;
    INC LR4 13 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR11 60 ; INC LR12 58 ; SET LR15 CR0 ;;
    INC LR15 6 ;;
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR1 46 ; INC LR2 35 ; INC LR3 43 ;;
    BEQ LR13 LR3 new_check_normal ;;
    SET LR3 CR0 ;;
    INC LR3 36 ;;
    BEQ LR13 LR3 new_check_normal ;;
    BLT.S LR1 LR13 new_check_normal ;;
    BLT.S LR13 LR2 new_check_normal ;;
    SET LR1 CR0 ;;
    B new_selected ;;
new_check_normal:
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR2 30 ; INC LR3 29 ;;
    BEQ LR13 LR14 new_mark ;;
    SET LR3 CR0 ;;
    INC LR3 56 ;;
    BEQ LR13 LR3 new_selected ;;
    SET LR3 CR0 ;;
    INC LR3 29 ;;
    BLT.S LR13 LR14 new_select ;;
    B new_selected ;;
new_select:
    BEQ LR13 LR11 new_selected ;;
    BEQ LR13 LR12 new_selected ;;
    SET LR11 CR0 ;;
    INC LR11 4 ;;
    BLT.S LR8 LR13 new_mark ;;
    BEQ LR2 LR13 new_mark ;;
    BEQ LR3 LR13 new_mark ;;
    BEQ LR9 LR13 new_mark ;;
    BEQ LR6 LR13 new_mark ;;
    BEQ LR7 LR13 new_mark ;;
    BEQ LR4 LR13 new_mark ;;
    BEQ LR15 LR13 new_mark ;;
    BEQ LR11 LR13 new_mark ;;
    B new_selected ;;
new_mark:
    SET LR1 CR1 ;;
new_selected:
    SET LR6 CR0 ; SET LR7 CR0 ;;
    INC LR7 32 ;;
new_row:
    SET LR4 LR10 ; LD.MULT.CYCLIC LR10 {{ w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0 ;;
    SET LR3 CR0 ; SET LR9 CR0 ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
    INC LR9 127 ; DEC LR3 1 ;;
new_pixel:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR3 1 ; INC LR6 1 ; DEC LR9 1 ; LD.MULT R0 LR6 {{ cr.in0 }} ; BNE LR9 CR1 new_pixel ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR3 1 ; INC LR6 1 ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0 ;;
    BEQ LR1 CR0 new_store ;;
new_correction:
    SUB LR6 LR6 {{ cr.width_rows }} ;;
    SUB LR3 LR0 CR1 ; SET LR9 {{ cr.scalar127 }} ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
new_correction_pixel:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR3 1 ; INC LR6 1 ; DEC LR9 1 ; LD.MULT R0 LR6 {{ cr.in0 }} ; BNE LR9 CR1 new_correction_pixel ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR3 1 ; INC LR6 1 ;;
new_store:
    {{ out('LR5',cr.full) }} ; INC LR5 1 ; DEC LR7 1 ; BNE LR7 CR1 new_row ;;
    INC LR10 4 ; DEC LR13 1 ; BNE LR13 CR1 new_feature ;;
    HALT ;;
{% else %}
{# Each input row is one pixel and one K chunk. Accumulate both coefficient
   digits directly into the output pixel slots. #}
    SET LR0 CR0 ; SET LR10 CR0 ; SET LR5 CR0 ;;
    SET LR13 {{ cr.n }} ; DEC LR5 1 ;;
direct_feature:
    SET LR11 CR0 ; SET LR12 LR15 ;;
direct_row:
    SET LR4 LR10 ; LD.MULT.CYCLIC LR10 {{ w }} LR0 ; SET LR7 {{ cr.width_rows }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR14 CR0 ; SET LR8 {{ cr.loop_count }} ;;
{% if spatial % group %}
    BLT.S LR12 LR7 direct_short ;;
    B direct_chunks ;;
direct_short:
    SET LR7 LR12 ;;
{% endif %}
direct_chunks:
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0 ;;
{% for digit in range(2) %}
    ADD LR6 LR11 LR14 ; SET LR3 CR0 ; SET LR9 LR7 ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR3 1 ; DEC LR9 1 ;;
    BEQ LR9 CR0 direct_last_{{ digit }} ;;
direct_pixel_{{ digit }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR3 1 ; ADD LR6 LR6 {{ cr.loop_count }} ; DEC LR9 1 ; LD.MULT R0 LR6 {{ cr.in0 }} ; BNE LR9 CR1 direct_pixel_{{ digit }} ;;
direct_last_{{ digit }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR3 1 {% if digit == 0 %}; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0{% endif %} ;;
{% endfor %}
    INC LR14 1 ; DEC LR8 1 ; BNE LR8 CR1 direct_chunks ;;
{% if spatial % group %}
    BLT.S LR12 {{ cr.width_rows }} direct_tail ;;
{% endif %}
    {{ out('LR5',cr.active) }} ; INC LR5 1 ; B direct_next ;;
{% if spatial % group %}
direct_tail:
    {{ out('LR5',cr.dot_tail) }} ; INC LR5 1 ;;
{% endif %}
direct_next:
    SUB LR12 LR12 LR7 ; SET LR6 LR7 ;;
{% if k > 128 %}
{% for i in range(((k + 127) // 128) - 1) %}
    ADD LR6 LR6 LR7 ;;
{% endfor %}
{% endif %}
    ADD LR11 LR11 LR6 ; BNE LR12 CR0 direct_row ;;
    INC LR10 {{ 2 + 2 * ((k + 127) // 128) }} ; DEC LR13 1 ; BNE LR13 CR1 direct_feature ;;
    HALT ;;
{% endif %}
{% if false %}
{# A broadcast coefficient updates a full spatial row. Stream the high
   and residual coefficient vectors into the two multiplier banks. #}
{% set pack3 = in0_d3 == 32 and in0_d2 % 4 == 0 and k <= 96 %}
{% set stride = (in0_d3+127)//128 %}
{% set wide_reduction = bias and k >= 256 and spatial > 1024 %}
{% set shallow = bias and k <= 64 %}
{# Full tap blocks can prefetch the next high-digit row on the last
   high-digit multiply. The residual multiply then loads the next tile. #}
{% set pipelined = wide_reduction or (k % 32 == 0 and in0_d3 <= 128 and not pack3) %}
{% set fused = pipelined and k % 32 == 0 and in0_d3 <= 128 %}
{% set fix = ((18 if pipelined else 22) if shallow else (16 if k >= 256 else 12)) if bias else (11 if pack3 else 14) %}
{% macro next_input() %}ADD LR6 LR6 LR4 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endmacro %}
{% macro block(taps, last=false, alternate=false) %}
{% if not pipelined %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ;;
{% endif %}
    INC LR7 1 ; LD.MULT R1 LR7 {{ w }} ; SUB LR1 LR0 CR1 ; SET LR2 {{ cr.scalar127 }} ;;
{% for j in range(taps) %}
{% set dual = ((j < 10 or j >= 22 if alternate else j < 21) or j == taps - 1) if wide_reduction else ((j == taps - 1 and pipelined) or j < fix - (1 if shallow and pipelined and not last else 0)) %}
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
    SET LR8 {{ cr.n }} ; {% if bias or pipelined %}SET LR9 CR0{% else %}SUB LR9 LR0 CR1{% endif %} ;;
feature:
    SET LR10 LR11 ; SET LR13 LR4 ;;
{% if stride > 1 %}
    SET LR3 {{ cr.width_rows }} ;;
{% endif %}
pixel:
    SET LR7 LR9 ; SET LR6 LR10 ; SET LR14 {{ cr.loop_count }} {% if bias or pipelined %}; LD.MULT.CYCLIC LR9 {{ w }} LR0{% endif %} ;;
{% if bias or pipelined %}
{% if shallow and pipelined %}
    {{ mac('CR1', true) }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% else %}
    {{ mac('CR1', true) }} ; INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ w }} LR0 ;;
    {{ mac('CR1') }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% endif %}
{% else %}
    {# No bias rows are stored for this path. Seed while loading the first input. #}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% endif %}
{% if pipelined %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ;;
{% endif %}
{% if k > 32 %}
{% if pipelined and ((k-1)//32)%2 %}
    {{ block(32) }}
{% endif %}
{% if not pipelined or k > 64 %}
block_loop:
    {{ block(32) }}
{% if pipelined %}
    {{ block(32, false, true) }}
{% endif %}
{% if not pipelined %}
    DEC LR14 1 ; BNE LR14 CR1 block_loop ;;
{% endif %}
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
    {% if bias or pipelined %}INC LR9 1 ; {% endif %}BNE LR8 CR0 feature ;;
    ADD LR11 LR11 LR15 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
{% else %}
{# Half-width spatial planes: transpose once, then reduce full K vectors. #}
{% set quad = k % 4 == 0 %}
{% set step = 4 if quad else 2 %}
{% macro copy_pair() %}MULT.VE LR4 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 {{ 4 if quad else 6 }}{% endmacro %}
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
{% if quad %}
    {# Four tap values per scatter: compact even and odd pixels into
       separate 32-wide stripes before gathering K vectors. #}
    SET LR8 LR5 ; SET LR9 {{ cr.width_rows }} ; SET LR3 CR0 ;;
    SET LR10 {{ cr.scalar127 }} ; INC LR3 2 ; DEC LR9 1 ;;
    SET LR1 CR0 ;;
    INC LR1 128 ;;
pack_quad:
    LD.MULT R0 LR8 {{ cr.panel }} ;;
    INC LR8 1 ; LD.MULT R1 LR8 {{ cr.panel }} ;;
{% for mode in ['on', 'on_inv'] %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.STRIDE 64 {{ mode }} off LR0 ;;
    MULT.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.STRIDE 64 {{ mode }} off LR3 ; INC LR9 1 ; {{ aq(cr.panel,'LR9',cr.full,cr.qf_in0) }} ;;
{% endfor %}
    INC LR8 1 ; DEC LR10 1 ; BNE LR10 CR1 pack_quad ;;
{% endif %}
    SET LR4 CR0 ; SET LR13 LR5 ; SET LR5 CR0 ;;
    SET LR0 CR0 ; SET LR1 LR6 ; INC LR7 64 ;;
{% if quad %}
    SET LR13 {{ cr.width_rows }} ; SET LR6 CR0 ;;
{% endif %}
    SET LR11 CR0 ;;
    INC LR11 2 ;;
gather_pixel:
    SET LR8 LR13 ; SET LR9 {{ cr.loop_count }} ;;
gather_chunk:
{% if quad and k % 128 == 0 %}
    SET LR2 CR0 ; SET LR3 LR14 ; SET LR10 CR0 ;;
    INC LR10 30 ; LD.MULT R0 LR8 {{ cr.panel }} ;;
    {{ copy_pair() }} ; INC LR8 2 ; LD.MULT R0 LR8 {{ cr.panel }} ;;
gather_quad_loop:
    {{ copy_pair() }} ; ADDBI LRD2 4 ; INC LR8 2 ; DEC LR10 1 ; LD.MULT R0 LR8 {{ cr.panel }} ; BNE LR10 CR1 gather_quad_loop ;;
    {# The store and scatter see the last loaded row before advancing. #}
    {{ copy_pair() }} ; ADDBI LRD2 4 ; INC LR8 2 ;;
{% else %}
    SET LR2 CR0 ; SET LR3 LR14 ; SET LR10 CR0 ;;
    INC LR10 {{ (k-1)%128//step+1 }} ;;
{% if k > 128 and k % 128 %}
    BEQ LR9 CR1 gather_start ;;
    SET LR10 CR0 ;;
    INC LR10 {{ 128 // step }} ;;
{% endif %}
gather_start:
    LD.MULT R0 LR8 {{ cr.panel }} ;;
    DEC LR10 1 ; {{ copy_pair() }} ; BEQ LR10 CR1 gather_single ;;
    INC LR8 {{ 2 if quad else 1 }} ; LD.MULT R0 LR8 {{ cr.panel }} ; BEQ LR10 CR1 gather_last ;;
gather_pair:
    ADDBI LRD2 {{ step }} ; DEC LR10 1 ; INC LR8 {{ 2 if quad else 1 }} ; {{ copy_pair() }} ; LD.MULT R0 LR8 {{ cr.panel }} ; BNE LR10 LR11 gather_pair ;;
gather_last:
    ADDBI LRD2 {{ step }} ; {{ copy_pair() }} ;;
gather_single:
    INC LR8 {{ 2 if quad else 1 }} ;;
{% endif %}
{% if k > 128 %}
    BEQ LR9 CR1 gather_tail ;;
    {{ aq(cr.panel,'LR5',cr.full,cr.qf_in0) }} ;;
    INC LR5 1 ; DEC LR9 1 ; B gather_chunk ;;
gather_tail:
{% endif %}
    {{ aq(cr.panel,'LR5',cr.dot_tail,cr.qf_in0) }} ;;
{% if quad %}
    DEC LR7 1 ; INC LR5 1 ; BEQ LR7 CR1 gather_done ;;
    BNE LR6 CR0 gather_even ;;
    INC LR13 1 ; INC LR6 1 ; B gather_pixel ;;
gather_even:
    ADDBI LRD0 1 ; DEC LR13 1 ; DEC LR6 1 ; B gather_pixel ;;
gather_done:
{% else %}
    ADDBI LRD0 1 ; DEC LR7 1 ; INC LR5 1 ; BNE LR7 CR1 gather_pixel ;;
{% endif %}
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
    {{ reduce() }} ; INC LR3 1 {% if bias %}; BEQ LR12 CR0 tiny_correction{% endif %} ;;
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
    {{ out('LR6',cr.k_tail) }} ;;
    INC LR6 1 ; DEC LR13 1 ; BNE LR13 CR1 tiny_feature ;;
    HALT ;;
{% endif %}
