{% set special = in0_d3 == 16 and n <= 128 and k % 128 == 0 and k <= 896 %}
{% if not ((in0_d3 >= 32 and n <= 128) or special) %}
{% macro mac(s, first=false, extra='') %}
    MULT.RC.VE LR0 {{ s }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 {{ extra }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ;;
{% endmacro %}
{# Keep correction rows for five taps per eight. The last partial block
   retains both digits for every tap. #}
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
    SET LR8 CR0 ; SET LR6 {{ cr.features }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ;;
tile:
    SUB LR5 LR2 {{ cr.pitch }} ; SET LR7 {{ cr.k }} ;;
    {{ mac('CR1', true) }}
    {{ mac('CR1') }}
{% if k >= 8 %}
    SET LR10 LR13 ;;
channel_block:
{% for tap_index in range(8) %}
    {{ tap(tap_index not in [1, 4, 7], '; DEC LR10 1 ; BNE LR10 CR1 channel_block' if loop.last else '') }}
{% endfor %}
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
{% if (in0_d3 >= 32 and n <= 128) or special %}
{# Accumulate along spatial lanes, then scatter each pixel's features.
   Store a correction plane to avoid rounding the dot product twice. #}
{% macro seed(idx, first='') %}
    MULT.EE {{ idx }} CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ first }}
{% endmacro %}
{% macro spatial_mac(idx) %}
    MULT.RC.VE LR0 {{ idx }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{% endmacro %}
{% macro panel_store() %}
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.panel }} LR3 ; INC LR3 1
{% endmacro %}
{% macro gather(load=true) %}
    MULT.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; AGG.SUM LR6 {{ cr.scalar_ds }}.L{% if load %} ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.panel }}{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ;;
    SET LR13 CR0 ; SET LR12 LR8 ; SUB LR3 LR0 CR1 ;;
    INC LR13 {% if special %}127{% else %}126{% endif %} ;;
spatial_panel:
    SUB LR7 LR0 CR1 ; SET LR9 {{ cr.features }} ;;
spatial_feature:
    INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ; SET LR5 LR2 ; SET LR10 {{ cr.k }} ;;
{% if special %}
    SET LR10 CR0 ;;
{% for j in range((k // 8 + 126) // 127) %}
    INC LR10 {{ [127, k // 8 - j * 127] | min }} ;;
{% endfor %}
{% endif %}
    {{ seed('LR0', '.FIRST') }} ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ;;
    {{ seed('LR0') }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
spatial_block:
    INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ; SUB LR1 LR0 CR1 ;;
    INC LR7 1 ; LD.MULT R1 LR7 {{ cr.coeff }} ; SET LR4 LR13 ;;
{% if not special %}    INC LR4 1 ;;
{% endif %}
spatial_tap:
{% if special %}
{% for j in range(8) %}
    {{ spatial_mac('LR1') }} ; INC LR1 1 {% if j % 2 == 1 %}; INC LR4 1{% endif %}{% if j == 7 %} ; DEC LR10 1 ; BEQ LR10 CR1 spatial_final_single{% elif j % 2 == 1 %} ; ADD LR5 LR5 {{ cr.pitch }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0{% endif %} ;;
{% if j % 2 == 0 %}
    {{ spatial_mac('LR4') }} ; INC LR4 1 ; ADD LR5 LR5 {{ cr.pitch }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
{% endif %}
{% endfor %}
    ADD LR5 LR5 {{ cr.pitch }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; BNE LR1 LR13 spatial_tap ;;
    B spatial_block ;;
spatial_final_single:
    {{ panel_store() }} ; B spatial_after_final ;;
{% else %}
    {{ spatial_mac('LR1') }} ; INC LR1 1 ; DEC LR10 1 ; BEQ LR10 CR1 spatial_final ;;
    {{ spatial_mac('LR4') }} ; INC LR4 1 ; ADD LR5 LR5 {{ cr.pitch }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; BNE LR1 LR13 spatial_tap ;;
    {# The branch compares the already advanced coarse index. #}
    {{ spatial_mac('LR1') }} ; INC LR1 1 ; DEC LR10 1 ; BEQ LR10 CR1 spatial_final ;;
    {{ spatial_mac('LR4') }} ; INC LR4 1 ; ADD LR5 LR5 {{ cr.pitch }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; B spatial_block ;;
spatial_final:
    {{ spatial_mac('LR4') }} ; INC LR4 1 ; {{ panel_store() }} ;;
{% endif %}
spatial_after_final:
    LD.MULT R0 LR3 {{ cr.panel }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
    {{ panel_store() }} ; DEC LR9 1 ; BNE LR9 CR1 spatial_feature ;;
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
    INC LR6 1 ; {{ gather() }} ; DEC LR10 1 ; BEQ LR10 CR1 gather_final ;;
    {{ gather() }} ; B gather_feature ;;
gather_final:
    {{ gather(false) }} ; INC LR3 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.last }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR1 1 ; INC LR11 1 ; BLT.S LR11 LR4 gather_pixel ;;
    DEC LR9 1 ; BEQ LR9 CR1 gather_next_batch ;;
    BLT.S LR1 {{ cr.packed_width }} gather_row ;;
    SET LR1 CR0 ; ADD LR2 LR2 {{ cr.features }} ;;
    ADD LR2 LR2 {{ cr.features }} ; B gather_row ;;
gather_next_batch:
    ADD LR2 LR2 {{ cr.features }} ;;
    ADD LR2 LR2 {{ cr.features }} ; DEC LR15 1 ; BNE LR15 CR1 gather_batch ;;
    HALT ;;
{% endif %}
