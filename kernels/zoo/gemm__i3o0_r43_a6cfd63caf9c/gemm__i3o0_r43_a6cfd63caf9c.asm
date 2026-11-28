{% set q = cr.qf_in0 ~ '.L' %}
{% set row_bits = 9 %}
{% set ds = cr.full ~ '.L' %}
{% macro move(src, acc) %}MULT.VE {{ src }} CR1 0 LR0 {{ ds }} {{ q }} ; {{ acc }}{% endmacro %}
{% macro save(base, ptr) %}ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ base }} {{ ptr }}{% endmacro %}
{% if in0_d0 == 4 and in0_d1 == 4 and in0_d2 == 64 and in0_d3 == 48 and k == 192 and m == 256 and out0_d0 == 4 and out0_d1 == 64 %}
{# Put the two token parities on the row axis and the tile bit on the lane axis.
   Row bits, low first: batch, parity, token-pair-within-tile, head. #}
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    INC LR4 128 ; INC LR5 48 ; INC LR6 176 ;;
    SET LR7 CR0 ; SET LR8 {{ cr.minusone }} ; SET LR9 {{ cr.minusone }} ;;
    INC LR7 2 ; INC LR9 4 ;;
{% macro pack(h) %}
{% set rlo = 'LR5' if h % 2 else 'LR0' %}
{% set rhi = 'LR6' if h % 2 else 'LR4' %}
    SET LR3 {{ 'CR1' if h // 2 else 'CR0' }} ; SET LR12 CR0 ;;
    INC LR12 16 ;;
pack_token_{{ h }}:
    SET LR1 LR3 ; LD.MULT R0 LR3 {{ cr.in0 }} ;;
{% for b in range(4) %}
    INC LR1 64 ; LD.MULT R1 LR1 {{ cr.in0 }} {% if b > 0 %}; {{ move(rhi, 'ACC.STRIDE 64 off on LR7') }} ; INC LR9 1 ; {{ save(cr.a, 'LR9') }}{% endif %} ;;
    {{ move(rlo, 'ACC.STRIDE 64 off on LR0') }} ; DEC LR1 62 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ move(rhi, 'ACC.STRIDE 64 off on LR7') }} ; INC LR8 1 ; {{ save(cr.a, 'LR8') }} ; INC LR1 64 ; LD.MULT R1 LR1 {{ cr.in0 }} ;;
    {{ move(rlo, 'ACC.STRIDE 64 off on LR0') }} {% if b < 3 %}; INC LR1 62 ; LD.MULT R0 LR1 {{ cr.in0 }}{% else %}; INC LR3 4{% endif %} ;;
{% endfor %}
    {{ move(rhi, 'ACC.STRIDE 64 off on LR7') }} ; INC LR9 1 ; {{ save(cr.a, 'LR9') }} ; INC LR8 4 ; DEC LR12 1 ;;
    INC LR9 4 ; BNE LR12 CR0 pack_token_{{ h }} ;;
{% endmacro %}
{% for h in range(in0_d1) %}{{ pack(h) }}{% endfor %}

{# Each pass trades one or two low row bits for selected lane bits.
   The selected lane bits become the high row bits of the next pass. #}
{% macro pass_stage(stage, src, dst, radix) %}
    SET LR1 CR0 ; SET LR2 {{ cr.minusone }} ; SET LR3 {{ cr.minusone }} ;;
    SET LR4 {{ cr.minusone }} ; SET LR5 {{ cr.minusone }} ; SET LR6 CR0 ;;
    ADD LR3 LR3 {{ cr.group }}.L{% if radix == 2 %} ; ADD LR6 LR6 {{ cr.group }}.L{% else %} ; INC LR6 {{ 128 * in0_d1 // radix }}{% endif %} ;;
{% if radix == 4 %}
    DEC LR3 {{ 128 * in0_d1 // radix }} ; ADD LR4 LR4 {{ cr.group }}.L ; ADD LR5 LR5 {{ cr.group }}.L ;;
    INC LR5 {{ 128 * in0_d1 // radix }} ;;
{% endif %}
    LD.MULT R0 LR1 {{ src }} ;;
pass{{ stage }}:
{% for mode in range(radix) %}
{% for i in range(radix) %}
{% set dest = 'LR' ~ (2 + mode) %}
{% set acc = 'ACC.STRIDE 16 ' ~ ('on_inv' if mode % 2 else 'on') ~ ' ' ~ (('on_inv' if mode >= 2 else 'on') if radix == 4 else 'off') ~ ' LR' ~ (8 + i * (4 // radix)) %}
    {{ move('LR0', acc) }} ; LD.MULT R0 LR1 {{ src }} ; {% if i == radix-1 and mode != radix-1 %}DEC LR1 {{ radix-1 }}{% else %}INC.MODP2 LR1 CR1 {{ row_bits }}{% endif %}{% if i == radix-1 %} ; INC {{ dest }} 1 ; {{ save(dst, dest) }}{% endif %}{% if mode == radix-1 and i == radix-1 %} ; DEC LR6 1 ; BNE LR6 CR1 pass{{ stage }}{% endif %} ;;
{% endfor %}
{% endfor %}
{% endmacro %}
    SET LR8 CR0 ; SET LR9 CR1 ; SET LR10 CR0 ;;
    INC LR10 2 ; SET LR11 CR0 ;;
    INC LR11 3 ;;
    {{ pass_stage(1, cr.a, cr.b, 4) }}
    {{ pass_stage(2, cr.b, cr.a, 4) }}
    {{ pass_stage(3, cr.a, cr.b, 2) }}
    {{ pass_stage(4, cr.b, cr.a, 2) }}

{# Last pass: compact valid features, separating the two sample tiles. #}
    SET LR1 CR0 ; SET LR2 {{ cr.minusone }} ; SET LR3 {{ cr.minusone }} ;;
    INC LR3 {{ k }} ; SET LR7 CR0 ; LD.MULT R0 LR1 {{ cr.a }} ;;
    INC LR7 4 ;;
compact:
{% for t in range(2) %}
{% for f1 in range(2) %}
{% for f4 in range(2) %}
{% set dst = 'LR' ~ (2 + t) %}
    SET LR6 CR0 ;;
    INC LR6 {{ 2 * in0_d1 }} ;;
compact_{{ t }}_{{ f1 }}_{{ f4 }}:
{% for f5 in range(2-f4) %}
    {{ move('LR0', 'ACC.STRIDE 16 ' ~ ('on_inv' if f5 else 'on') ~ ' off LR0') }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.a }} ;;
    {{ move('LR0', 'ACC.STRIDE 16 ' ~ ('on_inv' if f5 else 'on') ~ ' off LR10') }} ; {% if not f4 and not f5 %}DEC LR1 1{% else %}INC.MODP2 LR1 CR1 {{ row_bits }}{% endif %} ; LD.MULT R0 LR1 {{ cr.a }} ; INC {{ dst }} 1 ; {{ save(cr.panel, dst) }}{% if f4 or f5 %} ; DEC LR6 1 ; BNE LR6 CR1 compact_{{ t }}_{{ f1 }}_{{ f4 }}{% endif %} ;;
{% endfor %}
{% endfor %}
{% endfor %}
{% endfor %}
    DEC LR7 1 ; BNE LR7 CR1 compact ;;

{# Both coefficient chunks are resident before the first MAC. Combine the
   last MAC with the output store; no intermediate dot-product rounding. #}
    SET LR5 {{ cr.minusone }} ; SET LR6 {{ cr.minusone }} ; SET LR10 LR15 ;;
    SET LR9 CR0 ; SET LR11 CR0 ;;
    INC LR9 63 ; INC LR11 253 ;;
channel:
    INC LR6 1 ; LD.MULT R0 LR6 {{ cr.w }} ; SET LR2 {{ cr.minusone }} ;;
    INC LR6 1 ; LD.MULT R1 LR6 {{ cr.w }} ;;
{% macro dot(t) %}
    MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ; SET LR3 LR9 {% if not t %}; INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.panel }} LR0{% endif %} ;;
dot_{{ t }}:
    MULT.RC.VE LR0 LR3 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ; INC LR3 1 ; INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.panel }} LR0 ; BLT.S LR3 LR11 dot_{{ t }} ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ; INC LR3 1 ; INC LR5 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 {% if not t %}; INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.panel }} LR0{% else %}; DEC LR10 1 ; BNE LR10 CR1 channel{% endif %} ;;
{% endmacro %}
    {{ dot(0) }}
    {{ dot(1) }}
    HALT ;;
{% else %}
{% macro init(reg, value) %}
    SET {{ reg }} CR0 ;;
{% for i in range(17) %}
{% if i and ((value // (2 ** (17-i))) > 0) %}    ADD {{ reg }} {{ reg }} {{ reg }} ;;{% endif %}
{% if (value // (2 ** (16-i))) % 2 %}    INC {{ reg }} 1 ;;{% endif %}
{% endfor %}
{% endmacro %}
{# General contiguous merge. Walk the packed input within each batch and
   scatter each scalar dot into its batch-fast output lane. #}
    SET LR5 {{ cr.minusone }} ; SET LR6 {{ cr.minusone }} ; SET LR10 LR15 ;;
    SET LR15 CR0 ;;
    INC LR15 127 ;;
channel_general:
    INC LR6 1 ; SET LR12 CR0 ; SET LR13 CR0 ;;
    SET LR8 CR0 ;;
    {{ init('LR9',out0_d1) }}
token_general:
    SET LR14 LR12 ;;
    {{ init('LR11',out0_d0) }}
sample_general:
    SET LR1 LR14 ; SET LR2 LR13 ; SET LR3 LR6 ;;
    LD.MULT R0 LR3 {{ cr.w }} ; INC LR3 1 ; SET LR7 {{ cr.inner }} ; SET LR4 {{ cr.minusone }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM.FIRST LR8 {{ cr.single }}.L ; LD.MULT R0 LR3 {{ cr.w }} ;;
scalar_general:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR2 LR4 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR8 {{ cr.single }}.L ; INC LR4 1 ; INC LR2 1 ; DEC LR7 1 ;;
    INC LR0 {{ 2 * in0_d3 }} ;;
    SET LR0 CR0 ; BNE LR2 LR0 input_ready ;;
    SET LR2 CR0 ; INC LR1 1 ;;
input_ready:
    BEQ LR7 CR0 sample_done ;;
    BNE LR4 LR15 scalar_general ;;
    INC LR3 1 ; LD.MULT R0 LR3 {{ cr.w }} ; SET LR4 {{ cr.minusone }} ; B scalar_general ;;
sample_done:
    INC LR8 1 ; DEC LR11 1 ; ADD LR14 LR14 {{ cr.batch_rows }} ; BNE LR8 LR15 keep_tile ;;
    INC LR5 1 ; SET LR8 CR0 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
keep_tile:
    BNE LR11 CR0 sample_general ;;
    SUB LR1 LR1 LR14 ; DEC LR9 1 ; SET LR13 LR2 ;;
    ADD LR12 LR12 LR1 ;;
    ADD LR12 LR12 {{ cr.batch_rows }} ; BNE LR9 CR1 token_general ;;
{% if m % 128 %}
    INC LR5 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.group }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endif %}
    SET LR6 LR3 ; DEC LR10 1 ; BNE LR10 CR1 channel_general ;;
    HALT ;;
{% endif %}
