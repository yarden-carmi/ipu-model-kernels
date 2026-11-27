{% macro mac(src, acc='ACC.ADD', slot='LR0') %}
    MULT.RC.VE {{ slot }} {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ acc }}
{%- endmacro %}
{% set unroll_panels = panel_count <= 10 %}
{% set resident = centered and k == 32 and n <= 128 %}
{# Keep output channels on the MAC lanes. Each scratch panel holds eight
   spatial positions for each of sixteen taps, gathered from the input layout. #}
{% macro coeff() %}
    INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro store(ds) %}
    INC LR3 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3
{%- endmacro %}
{% macro pack_panel(count, stride, preload=false) %}
    SET LR4 LR14 ; SET LR5 LR15 ; SET LR6 LR14 ; LD.MULT R0 LR2 {{ stride[0] }} ;;
    SET LR7 LR15 ; ADDB LRD4 LR9 ;;
{% for tap in range(count) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD6 0
    {%- if not loop.first %} ; ADDBI LRD6 8{% endif %}
    {%- if loop.last %} ; ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR11 {% if preload %}; SET LR8 CR1 ; LD.MULT R1 LR8 {{ cr.panel }}{% endif %}
    {%- else %} ; {{ stride[1] }} ; LD.MULT R0 LR2 {{ stride[0] }}{% endif %} ;;
{% endfor %}
    {% if not resident %}INC LR11 1 ;;{% endif %}
{%- endmacro %}
{% macro panel_mac(count, load_next, final) %}
{% for tap in range(count) %}
    {% if (centered and k == 64 and count == 16 and load_next != 'sum' and tap % 8 == 7) or (not centered and ((k == 96 and n > 64 and tap >= 16 - split_taps) or ((k != 96 or n <= 64) and tap < split_taps))) %}
    {{ mac('LR1') }} ; {{ coeff() }} {% if not loop.first %}; INC LR1 8{% endif %} ;;
    {{ mac('LR1') }}
    {% else %}
    {{ mac('LR1') }} {% if not loop.first %}; INC LR1 8{% endif %}
    {% endif %}
    {%- if not (loop.last and final) %} ; {{ coeff() }}{% endif %}
    {%- if loop.last and final and n <= 128 %} ; {{ store(cr.tail_ds) }} ; INC LR2 1 {% if k == 16 %}; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0{% endif %} ; BLT.S LR2 LR5 {{ 'block' if k == 16 else 'pixel' }}{% endif %} ;;
{% endfor %}
{% if load_next == true %}
    LD.MULT R1 LR11 {{ cr.panel }} ; INC LR11 1 ; SET LR1 LR2 ;;
{% endif %}
{%- endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR13 CR0 ;;
    DEC LR3 1 ; SET LR12 {{ cr.plane }} ; SET LR9 CR0 ;;
{% for i in range(5) %}
    {% if i %}INC LR9 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR9 ;;
{% endfor %}
{% if narrow %}
{# Two adjacent 64-channel coefficient vectors share each cyclic row. #}
    INC LR1 128 ; INC LR7 64 ; INC LR11 192 ;;
    ADD LR4 LR1 LR1 ; SET LR14 {{ cr.pixels }} ;;
    ADD LR6 LR4 LR1 ; DEC LR14 1 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR4 ;;
    SET LR8 CR1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR6 ;;
group:
    SET LR9 CR0 ;;
pixel:
    SET LR8 CR1 ; SET LR2 LR13 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST', 'LR4') }} ; {{ coeff() }} ; ADD LR15 LR9 LR1 ;;
    {{ mac('CR1', 'ACC.ADD', 'LR6') }} ; INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR1 ;;
{% for pair in range(k // 2) %}
    {{ mac('LR9') }} ; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R1 LR2 {{ cr.in0 }} ;;
    {{ mac('LR9', 'ACC.ADD', 'LR1') }} {% if not loop.last %}; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R0 LR2 {{ cr.in0 }}{% endif %} ;;
    {{ mac('LR15', 'ACC.ADD', 'LR7') }} {% if not loop.last %}; {{ coeff() }}{% endif %} ;;
    {{ mac('LR15', 'ACC.ADD', 'LR11') }} ; {% if loop.last %}{{ store(cr.tail_ds) }} ; INC LR9 1 ; BLT.S LR9 LR14 pixel{% else %}INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR1{% endif %} ;;
{% endfor %}
    INC LR13 1 ; DEC LR10 1 ; DEC LR12 1 ; BEQ LR10 CR1 end ;;
    BNE LR12 CR0 group ;;
    ADD LR13 LR13 {{ cr.batch_skip }} ; SET LR12 {{ cr.plane }} ; B group ;;
{% elif packed %}
group:
{% if centered %}
{# The shared coefficient offset multiplies the sum of its four input taps. #}
    SET LR2 LR13 ; SET LR11 CR0 ; SET LR8 {{ cr.k }} ;;
    INC LR11 {{ panel_count - 1 }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
sum_group:
{% for tap in range(4) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ 'ACC.ADD.FIRST' if loop.first else 'ACC.ADD' }} ; ADD LR2 LR2 {{ cr.plane }}
    {%- if loop.last %} ; ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR11 ; INC LR11 1 ; DEC LR8 4
    {%- else %} ; LD.MULT R0 LR2 {{ cr.in0 }}{% endif %} ;;
{% endfor %}
    BEQ LR8 CR0 sums_ready ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ; B sum_group ;;
sums_ready:
{% endif %}
    SET LR9 CR0 ;;
tile:
{% if resident %}
{# Keep the second panel in R1 and the first bias component in its own
   cyclic slot so the final MAC can reload R0 for the next pixel. #}
    SET LR2 LR13 ; SET LR11 CR0 ;;
    {{ pack_panel(16, (cr.in0, 'ADD LR2 LR2 ' ~ cr.plane)) }}
    ADD LR2 LR2 {{ cr.plane }} ; INC LR11 1 ;;
    {{ pack_panel(16, (cr.in0, 'ADD LR2 LR2 ' ~ cr.plane)) }}
    INC LR11 1 ;;
    SET LR2 LR11 ; INC LR11 {{ sum_count }} ;;
    {{ pack_panel(sum_count, (cr.panel, 'INC LR2 1'), true) }}
    SET LR2 CR0 ; SET LR6 CR0 ; SET LR5 CR0 ; LD.MULT R0 LR0 {{ cr.panel }} ;;
    INC LR6 128 ; INC LR5 7 ;;
    ADD LR7 LR6 LR6 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR7 ;;
resident_pixel:
    {{ mac('CR1', 'ACC.ADD.FIRST', 'LR7') }} ; SET LR8 CR1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; SET LR1 LR2 ;;
    {{ mac('CR1') }} ; {{ coeff() }} ;;
{% for panel in range(3) %}
    {% set p = panel %}
    {% for tap in range(8 if p == 2 else 16) %}
    {{ mac('LR4') }} ; SET LR4 LR1
    {%- if p == 2 and loop.last %} ; {{ store(cr.tail_ds) }} ; INC LR2 1 ; LD.MULT R0 LR0 {{ cr.panel }} ; BLT.S LR2 LR5 resident_pixel
    {%- else %} ; {{ coeff() }}
        {%- if not loop.last %} ; INC LR1 8
        {%- elif p == 0 %} ; ADD LR1 LR2 LR6
        {%- else %} ; SET LR1 LR2{% endif %}
    {%- endif %} ;;
    {% endfor %}
    {% if p == 0 %}LD.MULT R0 LR11 {{ cr.panel }} ;;{% endif %}
{% endfor %}
{% else %}
    SET LR2 LR13 ; SET LR11 CR0 ; SET LR8 {{ cr.k }} ;;
gather:
    {{ pack_panel(16, (cr.in0, 'ADD LR2 LR2 ' ~ cr.plane)) }}
    DEC LR8 16 ; ADD LR2 LR2 {{ cr.plane }} ;;
    BNE LR8 CR0 gather ;;
{% if centered %}
    SET LR2 LR11 ; INC LR11 {{ sum_count }} ;;
    {{ pack_panel(sum_count, (cr.panel, 'INC LR2 1')) }}
{% endif %}
    SET LR2 CR0 ;;
    INC LR2 128 ;;
    SET LR5 LR2 ;;
    INC LR5 7 ;;
{% if k == 16 %}
    LD.MULT R1 LR0 {{ cr.panel }} ;;
{% endif %}
pixel:
    SET LR8 CR0 ; SET LR6 {{ cr.blocks }} ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
block:
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {% if k == 16 and n <= 128 %}SET LR8 CR1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0{% else %}{{ coeff() }}{% endif %} ; SET LR11 CR0 {% if n > 128 %}; DEC LR6 1{% endif %} ;;
    {{ mac('CR1') }} ; {{ coeff() }} ; SET LR1 LR2 {% if not centered and k > 16 %}; SET LR7 {{ cr.k }}{% endif %} ;;
{% if k != 16 %}
    LD.MULT R1 LR11 {{ cr.panel }} ;;
{% endif %}
{% if centered %}
    {% for panel in range(panel_count) %}
    {{ panel_mac(16, not loop.last, false) }}
    {% endfor %}
    SET LR11 CR0 ;;
    INC LR11 {{ panel_count + sum_count }} ; LD.MULT R1 LR11 {{ cr.panel }} ; SET LR1 LR2 ;;
    {{ panel_mac(sum_count, 'sum', true) }}
{% elif k == 16 %}
    {{ panel_mac(16, false, true) }}
{% elif unroll_panels %}
    {% for panel in range(panel_count) %}
    {{ panel_mac(16, not loop.last, loop.last) }}
    {% endfor %}
{% else %}
reduce:
    DEC LR7 16 ;;
    {{ panel_mac(16, false, false) }}
    BEQ LR7 CR0 write_block ;;
    LD.MULT R1 LR11 {{ cr.panel }} ; INC LR11 1 ; SET LR1 LR2 ; B reduce ;;
{% endif %}
{% if n > 128 or not unroll_panels %}
write_block:
    {% if n > 128 %}BNE LR6 CR0 write_full ;;{% endif %}
    {{ store(cr.tail_ds) }} ; INC LR2 1 ; BLT.S LR2 LR5 pixel ;;
{% endif %}
{% endif %}
    INC LR9 8 ;;
    BLT.S LR9 {{ cr.pixels }} tile ;;
    INC LR13 1 ; DEC LR10 1 ; DEC LR12 1 ; BEQ LR10 CR1 end ;;
    BNE LR12 CR0 group ;;
    ADD LR13 LR13 {{ cr.batch_skip }} ; SET LR12 {{ cr.plane }} ; B group ;;
{% if n > 128 and not resident %}
write_full:
    {{ store(cr.full_ds) }} {% if unroll_panels %}; {{ coeff() }}{% endif %} ; B block ;;
{% endif %}
{% else %}
group:
    SET LR9 CR0 ;;
pixel:
    SET LR8 CR0 ; SET LR6 {{ cr.blocks }} ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
block:
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {{ coeff() }} ; SET LR2 LR13 ; DEC LR6 1 ;;
    {{ mac('CR1') }} ; {{ coeff() }} ; SET LR1 CR0 ; SET LR7 {{ cr.k }} ;;
    INC LR1 128 ; ADD LR1 LR1 LR9 ; LD.MULT R1 LR2 {{ cr.in0 }} ;;
reduce:
    {{ mac('LR1') }} ; {{ coeff() }} ; DEC LR7 1 ; BEQ LR7 CR1 last_tap ;;
    {{ mac('LR1') }} ; {{ coeff() }} ; ADD LR2 LR2 {{ cr.plane }} ;;
    LD.MULT R1 LR2 {{ cr.in0 }} ; B reduce ;;
last_tap:
    {{ mac('LR1') }} ; BNE LR6 CR0 write_full ;;
    {{ store(cr.tail_ds) }} ; INC LR9 1 ; BLT.S LR9 {{ cr.pixels }} pixel ;;
    INC LR13 1 ; DEC LR10 1 ; DEC LR12 1 ; BEQ LR10 CR1 end ;;
    BNE LR12 CR0 group ;;
    ADD LR13 LR13 {{ cr.batch_skip }} ; SET LR12 {{ cr.plane }} ; B group ;;
write_full:
    {{ store(cr.full_ds) }} ; {{ coeff() }} ; B block ;;
{% endif %}
end:
    HALT ;;
