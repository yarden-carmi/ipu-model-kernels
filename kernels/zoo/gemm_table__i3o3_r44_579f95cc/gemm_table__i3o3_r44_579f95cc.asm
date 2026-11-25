{# Each spatial stripe has contiguous input taps and output channels.
   Pipeline the next channel's first coefficient row in the store word. #}
{% macro coeff(reg) -%}
INC LR7 1 ; LD.MULT {{ reg }} LR7 {{ cr.coeff }}
{%- endmacro %}
{% macro input() -%}
LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{%- endmacro %}
{% macro next_input() -%}
{{ 'DEC' if in0_d3 > 64 and 16 < k <= 32 else 'INC' }} LR6 1 ; {{ input() }}
{%- endmacro %}
{% macro mac(src) -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
{% macro bias_mac(src, first=false) -%}
MULT.EE {{ src }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro store() -%}
ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
{%- endmacro %}
{% macro finish() -%}
{{ store() }} ; {{ coeff('R0') }} ; DEC LR8 1 ; BNE LR8 CR1 channel
{%- endmacro %}
{% macro pairs(taps, block=false, compact=false) %}
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1{% if loop.first and compact %} ; {{ coeff('R1') }}{% elif loop.last and (block or compact) %} ; {{ coeff('R0') }}{% endif %} ;;
    {{ mac('LR2') }} ; INC LR2 1{% if loop.first and compact %} ; INC LR4 1{% endif %}{% if not loop.last or compact %} ; {{ next_input() }}{% elif not block %} ; {{ finish() }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro indices() -%}
SUB LR1 LR0 CR1 ; SET LR2 LR13
{%- endmacro %}

{% if in0_d3 <= 32 %}
{% macro transpose(taps, tag) %}
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR9 CR0 ;;
pixel_{{ tag }}:
    SET LR6 LR11 ; SET LR3 CR0 ; SET LR13 CR0 ;;
    INC LR13 {{ taps }} ; {{ input() }} ;;
    MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
tap_{{ tag }}:
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD2 7 ; DEC LR13 1 ; BEQ LR13 CR1 packed_{{ tag }} ;;
    {{ next_input() }} ; ADDBI LRD2 1 ; B tap_{{ tag }} ;;
packed_{{ tag }}:
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.pixels }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.pixels }} ;;
    INC LR1 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.pixels }} LR1 ;;
    INC LR1 1 ; ADDBI LRD4 1 ; INC LR9 1 ; BNE LR9 LR8 pixel_{{ tag }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR10 {{ cr.stripes }} ; SET LR11 CR0 ;;
    SET LR12 CR0 ; SET LR8 CR0 ; SET LR2 CR0 ;;
    INC LR8 {{ in0_d3 - 1 }} ; DEC LR12 1 ; SET LR15 CR0 ;;
{% for segment in range(5) %}
    {% if segment %} INC LR15 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR15 ;;
{% endfor %}
narrow_stripe:
    SET LR1 CR0 ; SET LR14 {{ cr.aux }} ;;
{% if k > 128 %}
transpose_panel:
    BEQ LR14 CR1 transpose_tail ;;
    {{ transpose(128, 'full') }}
    INC LR11 128 ; DEC LR14 1 ; B transpose_panel ;;
transpose_tail:
{% endif %}
    {{ transpose((k - 1) % 128 + 1, 'last') }}
    INC LR11 {{ (k - 1) % 128 + 1 }} ; SET LR7 CR0 ; SET LR9 {{ cr.n }} ;;
    DEC LR7 1 ; SET LR13 CR0 ;;
    INC LR13 128 ;;
narrow_channel:
    {{ coeff('R0') }} ; SET LR1 CR0 ; SET LR14 {{ cr.aux }} ;;
    {{ bias_mac('LR0', true) }} ; {{ coeff('R1') }} ; DEC LR1 1 ;;
    {{ bias_mac('LR13') }} ; INC LR12 1 ;;
dot_panel:
    {{ coeff('R0') }} ; SET LR3 CR0 ;;
    {{ coeff('R1') }} ;;
    INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.pixels }} LR0 ;;
{% for pixel in range(in0_d3) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.pixels }} LR0{% if not loop.first %} ; INC LR3 1{% endif %} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; DEC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.pixels }} LR0 ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L{% if not loop.last %} ; INC LR1 2 ; LD.MULT.CYCLIC LR1 {{ cr.pixels }} LR0{% else %} ; INC LR1 1 ; DEC LR14 1 ; BNE LR14 CR1 dot_panel{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR12 ; DEC LR9 1 ; BNE LR9 CR1 narrow_channel ;;
    DEC LR10 1 ; BNE LR10 CR1 narrow_stripe ;;
    HALT ;;
{% elif in0_d3 == 64 %}
{% macro stage_input() -%}
INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.pixels }} LR15
{%- endmacro %}
{% macro second_input() -%}
INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR12
{%- endmacro %}
{% macro packed_mac(src) -%}
MULT.RC.VE LR11 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
{% macro packed_taps(count) %}
    SET LR11 CR0 ; SET LR15 CR0 ;;
    INC LR11 64 ; ADD LR15 LR15 {{ cr.full }}.H ; ADD LR12 LR12 {{ cr.full }}.H ;;
{% for j in range(count) %}
{% if not loop.first %}
    {{ 'ADD' if j % 2 else 'SUB' }} LR11 LR11 {{ cr.full }}.H ; {{ 'SUB' if j % 2 else 'ADD' }} LR15 LR15 {{ cr.full }}.H ; {{ 'SUB' if j % 2 else 'ADD' }} LR12 LR12 {{ cr.full }}.H ;;
{% endif %}
    {{ packed_mac('LR1') }} ; INC LR1 1{% if not loop.last %} ; {{ stage_input() }}{% endif %} ;;
    {{ packed_mac('LR2') }} ; INC LR2 1{% if not loop.last %} ; {{ second_input() }}{% endif %} ;;
{% endfor %}
    SET LR12 CR0 ;;
    INC LR12 128 ; SET LR15 CR0 ; SET LR11 CR0 ;;
    INC LR11 64 ;;
{% endmacro %}
{% macro unpack(start, residual, dst) %}
    MULT.VE {{ start }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE {{ residual }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ store() | replace('LR4', dst) }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR3 CR0 ;;
    SET LR10 {{ cr.stripes }} ; SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR11 64 ; INC LR12 128 ; SET LR13 CR0 ;;
    INC LR13 127 ; SET LR15 CR0 ; SET LR4 CR0 ;;
    INC LR15 255 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
pair_stripe:
    SET LR6 LR5 ; SET LR9 CR0 ; SET LR14 {{ cr.k }} ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
    DEC LR6 1 ; DEC LR9 1 ;;
shift_input:
    INC LR6 1 ; LD.MULT R1 LR6 {{ cr.in0 }} ;;
    MULT.VE LR11 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR9 1 ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.pixels }} LR9 ; DEC LR14 1 ; BNE LR14 CR1 shift_input ;;
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; ADD LR4 LR3 {{ cr.n }} ;;
    LD.MULT R0 LR0 {{ cr.coeff }} ;;
pair_channel:
    SET LR6 LR5 ; SET LR9 CR0 ; BEQ LR10 CR1 pair_input_base ;;
    ADD LR6 LR6 {{ cr.k }} ;;
pair_input_base:
    DEC LR6 1 ; DEC LR9 1 ; SET LR15 CR0 ;;
    INC LR15 255 ;;
    MULT.EE LR13 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ coeff('R1') }} ;;
    MULT.EE LR15 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if k > 64 %} ; {{ coeff('R0') }}{% else %} ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.pixels }} LR0{% endif %} ;;
{% if k > 64 %}
    {{ coeff('R1') }} ;;
    INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.pixels }} LR0 ;;
{% endif %}
    {{ second_input() }} ; {{ indices() }} ;;
    SET LR14 {{ cr.full_blocks }} ;;
{% if k > 32 %}
pair_block:
    {{ packed_taps(32) }}
    {{ coeff('R0') }} ; {{ indices() }} ;;
    {{ coeff('R1') }} ;;
    {{ stage_input() }} ;;
    {{ second_input() }} ; DEC LR14 1 ; BNE LR14 CR1 pair_block ;;
{% endif %}
    {{ packed_taps((k - 1) % 32 + 1) }}
    SET LR9 {{ cr.aux }} ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.pixels }} LR9 ;;
    LD.MULT R0 LR9 {{ cr.pixels }} ;;
    INC LR9 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.pixels }} LR9 ;;
    LD.MULT R1 LR9 {{ cr.pixels }} ; SET LR14 LR12 ;;
    ADD LR14 LR14 LR11 ;;
    {{ unpack('LR0', 'LR12', 'LR3') }}
    INC LR3 1 ; BEQ LR10 CR1 pair_next_channel ;;
    {{ unpack('LR11', 'LR14', 'LR4') }}
    INC LR4 1 ;;
pair_next_channel:
    {{ coeff('R0') }} ; DEC LR8 1 ; BNE LR8 CR1 pair_channel ;;
    BEQ LR10 CR1 pair_end ;;
    ADD LR3 LR3 {{ cr.n }} ; ADD LR5 LR5 {{ cr.k }} ; DEC LR10 1 ;;
    ADD LR5 LR5 {{ cr.k }} ; DEC LR10 1 ; BNE LR10 CR1 pair_stripe ;;
pair_end:
    HALT ;;
{% else %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR4 CR0 ;;
    SET LR10 {{ cr.stripes }} ; SET LR13 CR0 ; SET LR15 CR0 ;;
    INC LR13 127 ; INC LR15 255 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
    DEC LR4 5 ;;
{% if in0_d3 > 64 and 16 < k <= 32 %}
    INC LR5 {{ k - 1 }} ;;
{% endif %}
stripe:
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; LD.MULT R0 LR0 {{ cr.coeff }} ;;
channel:
{% if in0_d3 > 64 and 16 < k <= 32 %}
    {{ bias_mac('LR13', true) }} ; SET LR6 LR5 ; {{ input() }} ; {{ indices() }} ;;
{% else %}
    {{ bias_mac('LR13', true) }} ; {{ coeff('R1') }} ; SET LR6 LR5 ;;
{% endif %}
{% if k > 64 %}
    {{ bias_mac('LR15') }} ; {{ coeff('R0') }} ; INC LR4 1 ;;
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ input() }} ; SET LR14 {{ cr.full_blocks }} ;;
{% elif not (in0_d3 > 64 and 16 < k <= 32) %}
    {{ bias_mac('LR15') }} ; {{ input() }} ; INC LR4 1 ; {{ indices() }} ;;
{% endif %}
{% if k > 32 %}
{% if k <= 64 %}
    SET LR14 {{ cr.full_blocks }} ;;
{% endif %}
full_block:
    {{ pairs(32, true) }}
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ next_input() }} ; DEC LR14 1 ; BNE LR14 CR1 full_block ;;
{% endif %}
{% if in0_d3 > 64 and 16 < k <= 32 %}
    {{ pairs(k - 2, compact=true) }}
    {{ mac('LR0') }} ; {{ next_input() }} ; SET LR1 CR1 ;;
    {{ mac('LR1') }} ; {{ finish() }} ;;
{% else %}
    {{ pairs((k - 1) % 32 + 1) }}
{% endif %}
    ADD LR5 LR5 {{ cr.k }} ; DEC LR10 1 ; BNE LR10 CR1 stripe ;;
    HALT ;;
{% endif %}
