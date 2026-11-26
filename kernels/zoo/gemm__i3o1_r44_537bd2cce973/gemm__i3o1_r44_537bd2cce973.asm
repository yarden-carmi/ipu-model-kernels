{% if not (in0_d3 >= 32 and n <= 128) %}
{% set precise = k >= 256 %}
{% set transpose = not precise and n > 128 and k % 8 == 0 %}
{% macro mac(s, first=false, extra='') %}
    MULT.RC.VE LR0 {{ s }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 {{ extra }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ;;
{% endmacro %}
{# Long reductions and partial blocks use both coefficient digits. #}
{% macro tap(dual, tail='') %}
    LD.MULT R0 LR5 {{ cr.in0 }} ; ADD LR5 LR5 {{ cr.pitch }} ; DEC LR7 1 ;;
{% if dual %}
    {{ mac('LR1') }}
{% endif %}
    {{ mac('LR1', false, tail) }}
{% endmacro %}
    SET LR0 CR0 ; SET LR12 CR0 ;;
    SUB LR3 LR0 CR1 ;;
batch:
    SET LR2 LR12 ; SET LR9 {{ cr.in0_d2 }} ; SET LR1 CR0 ;;
row:
    SET LR11 CR0 ;;
pixel:
{% if transpose %}
{# Gather one pixel's input channels once and reuse them across output tiles. #}
    SET LR5 LR2 ; SET LR7 {{ cr.k }} ; SUB LR10 LR0 CR1 ;;
    SET LR13 CR0 ;;
    INC LR13 127 ;;
input_chunk:
    SUB LR4 LR0 CR1 ; SUB LR6 LR7 CR1 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
    BLT.S LR6 LR13 input_limit ;;
    SET LR6 LR13 ;;
input_limit:
    DEC LR6 2 ; MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
input_gather:
    MULT.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR4 {{ cr.scalar_ds }}.L ; INC LR4 1 ; ADD LR5 LR5 {{ cr.pitch }} ; DEC LR7 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; BLT.S LR4 LR6 input_gather ;;
    MULT.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR4 {{ cr.scalar_ds }}.L ; INC LR4 1 ; INC LR10 1 ; DEC LR7 1 ; BEQ LR7 CR1 input_final ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR10 ; ADD LR5 LR5 {{ cr.pitch }} ; B input_chunk ;;
input_final:
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR10 ; SET LR4 CR0 ;;
{% if in0_d3 > 1 %}
    INC LR4 {{ in0_d3 - 1 }} ;;
{% endif %}
{% endif %}
    SET LR8 CR0 ; SET LR6 {{ cr.features }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ;;
tile:
{% if transpose %}
    SET LR5 CR0 ; SET LR7 {{ cr.k }} ;;
{% else %}
    SUB LR5 LR2 {{ cr.pitch }} ; SET LR7 {{ cr.k }} ;;
{% endif %}
    {{ mac('CR1', true) }}
    {{ mac('CR1') }}
{% if transpose %}
transposed_chunk:
    LD.MULT R0 LR5 {{ cr.panel }} ; SUB LR10 LR0 CR1 ;;
transposed_block:
{% set step = 16 if k % 16 == 0 else 8 %}
{% for j in range(step) %}
    {{ mac('LR10', false, '; INC LR10 1' ~ (' ; DEC LR7 ' ~ step if loop.last else '')) }}
{% endfor %}
    BEQ LR7 CR0 transposed_done ;;
    BLT.S LR10 LR13 transposed_block ;;
    INC LR5 1 ; B transposed_chunk ;;
transposed_done:
{% else %}
{% if k >= 8 %}
    SET LR10 LR13 ;;
channel_block:
{% for tap_index in range(8) %}
    {{ tap(precise, '; DEC LR10 1 ; BNE LR10 CR1 channel_block' if loop.last else '') }}
{% endfor %}
{% endif %}
{% endif %}
{% if k % 8 %}
channel_tail:
    {{ tap(true, '; BNE LR7 CR0 channel_tail') }}
{% endif %}
    BEQ LR6 CR1 last ;;
    {{ store(cr.full) }}
    DEC LR6 1 ; B tile ;;
last:
    {{ store(cr.last) }}
    INC LR1 1 ; INC LR11 1 ; BLT.S LR11 LR4 pixel ;;
    DEC LR9 1 ; BEQ LR9 CR1 next_batch ;;
    BLT.S LR1 {{ cr.packed_width }} row ;;
    SET LR1 CR0 ; INC LR2 1 ; B row ;;
next_batch:
    ADD LR12 LR12 LR14 ; DEC LR15 1 ; BNE LR15 CR1 batch ;;
    HALT ;;
{% endif %}
{% if in0_d3 >= 32 and n <= 128 %}
{% set residual = in0_d3 < 128 and k != 128 %}
{% set panel_qf = cr.scalar_ds ~ '.H' if k == 128 else cr.qf_out0 ~ '.L' %}
{# Accumulate along spatial lanes, then scatter each pixel's features.
   Use a wider-exponent scratch row for the fully corrected 128-tap path,
   and a residual plane for other packed spatial reductions. #}
{% macro seed(idx, first='') %}
    MULT.EE {{ idx }} CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ first }}
{% endmacro %}
{% macro spatial_mac(idx) %}
    MULT.RC.VE LR0 {{ idx }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{% endmacro %}
{% macro panel_store() %}
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ panel_qf }} {{ cr.panel }} LR3 ; INC LR3 1
{% endmacro %}
{% macro gather(load=true) %}
    MULT.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ panel_qf }} ; AGG.SUM LR6 {{ cr.scalar_ds }}.L{% if load %} ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.panel }}{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ;;
    SET LR13 CR0 ; SET LR12 LR8 ; SUB LR3 LR0 CR1 ;;
    INC LR13 126 ;;
spatial_panel:
    SUB LR7 LR0 CR1 ; SET LR9 {{ cr.features }} ;;
spatial_feature:
    INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ; SET LR5 LR2 ; SET LR10 {{ cr.k }} ;;
    {{ seed('LR0', '.FIRST') }} ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ;;
    {{ seed('LR0') }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
{% if k % 128 == 0 %}
{% if k > 128 %}
    SET LR11 CR0 ;;
{% for j in range((k // 128 + 127) // 128) %}
    INC LR11 {{ [128, k // 128 - j * 128] | min }} ;;
{% endfor %}
spatial_fast_block:
{% endif %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ; SUB LR1 LR0 CR1 ;;
    INC LR7 1 ; LD.MULT R1 LR7 {{ cr.coeff }} ; SET LR4 LR13 ; SET LR10 CR0 ;;
    INC LR10 8 ;;
    INC LR4 1 ;;
fast_tap:
{% for i in range(16) %}
{% set dual = k == 128 or i not in [1,3,5,9,11,13] %}
    {{ spatial_mac('LR1') }} ; INC LR1 1 {% if not dual %}; INC LR4 1 ; ADD LR5 LR5 {{ cr.pitch }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0{% endif %} {% if loop.last %}; BEQ LR10 CR1 spatial_last{% endif %} ;;
{% if dual %}
    {{ spatial_mac('LR4') }} ; INC LR4 1 ; ADD LR5 LR5 {{ cr.pitch }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 {% if loop.last %}; DEC LR10 1 ; B fast_tap{% endif %} ;;
{% endif %}
{% endfor %}
spatial_last:
    {{ spatial_mac('LR4') }} ; INC LR4 1 ;;
{% if k > 128 %}
    DEC LR11 1 ; BEQ LR11 CR1 spatial_final_fast ;;
    ADD LR5 LR5 {{ cr.pitch }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; B spatial_fast_block ;;
{% endif %}
spatial_final_fast:
    {{ panel_store() }} ;;
{% else %}
spatial_block:
    INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ; SUB LR1 LR0 CR1 ;;
    INC LR7 1 ; LD.MULT R1 LR7 {{ cr.coeff }} ; SET LR4 LR13 ;;
    INC LR4 1 ;;
spatial_tap:
    {{ spatial_mac('LR1') }} ; INC LR1 1 ; DEC LR10 1 ; BEQ LR10 CR1 spatial_final ;;
    {{ spatial_mac('LR4') }} ; INC LR4 1 ; ADD LR5 LR5 {{ cr.pitch }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; BNE LR1 LR13 spatial_tap ;;
    {# The branch compares the already advanced coarse index. #}
    {{ spatial_mac('LR1') }} ; INC LR1 1 ; DEC LR10 1 ; BEQ LR10 CR1 spatial_final ;;
    {{ spatial_mac('LR4') }} ; INC LR4 1 ; ADD LR5 LR5 {{ cr.pitch }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; B spatial_block ;;
spatial_final:
    {{ spatial_mac('LR4') }} ; INC LR4 1 ; {{ panel_store() }} ;;
{% endif %}
{% if residual %}
    LD.MULT R0 LR3 {{ cr.panel }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
    {{ panel_store() }} ;;
{% endif %}
    DEC LR9 1 ; BNE LR9 CR1 spatial_feature ;;
    INC LR2 1 ; DEC LR12 1 ; BNE LR12 CR1 spatial_panel ;;

    SUB LR3 LR0 CR1 ; SUB LR2 LR0 CR1 ; SET LR4 CR0 ;;
    INC LR4 {{ in0_d3 - 1 }} ;;
gather_batch:
    SET LR9 {{ cr.in0_d2 }} ; SET LR1 CR0 ;;
gather_row:
    SET LR11 CR0 ;;
gather_pixel:
    SET LR5 LR2 ; SET LR10 {{ cr.features }} ;;
    INC LR5 1 ; LD.MULT R0 LR5 {{ cr.panel }} ; SUB LR6 LR0 CR1 ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
gather_feature:
{% if residual %}
    INC LR6 1 ; {{ gather() }} ; DEC LR10 1 ; BEQ LR10 CR1 gather_last ;;
    {{ gather() }} ; B gather_feature ;;
gather_last:
    {{ gather(false) }} ;;
{% else %}
{% if n > 1 %}
    DEC LR10 1 ;;
gather_single:
    INC LR6 1 ; {{ gather() }} ; DEC LR10 1 ; BNE LR10 CR1 gather_single ;;
{% endif %}
    INC LR6 1 ; {{ gather(false) }} ;;
{% endif %}
gather_final:
    INC LR3 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.last }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR1 1 ; INC LR11 1 ; BLT.S LR11 LR4 gather_pixel ;;
    DEC LR9 1 ; BEQ LR9 CR1 gather_next_batch ;;
    BLT.S LR1 {{ cr.packed_width }} gather_row ;;
    SET LR1 CR0 ; ADD LR2 LR2 {{ cr.features }} ;;
{% if residual %}
    ADD LR2 LR2 {{ cr.features }} ;;
{% endif %}
    B gather_row ;;
gather_next_batch:
{% if residual %}
    ADD LR2 LR2 {{ cr.features }} ;;
{% endif %}
    ADD LR2 LR2 {{ cr.features }} ; DEC LR15 1 ; BNE LR15 CR1 gather_batch ;;
    HALT ;;
{% endif %}
