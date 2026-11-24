{# One input row supplies up to 128 consecutive channel scalars. The
   coefficient stream is pipelined through the cyclic register. #}
{% macro coeff_load() -%}
LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1
{%- endmacro %}
{% macro mac(src, op='ACC.ADD') -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{%- endmacro %}
{% macro store(ds) -%}
ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1
{%- endmacro %}

{% if m == 1 and in0_d0 * in0_d2 * in0_d3 == 1 and k == in0_d1 and k <= 640 %}
{% set tiles = (k + 127) // 128 %}
{% set groups = (n + 127) // 128 %}
{% set slots = ['LR0', 'LR1', 'LR11', 'LR12'] %}
{# Keep up to four input chunks resident. A five-chunk dot streams its
   final two chunks through slot 3 while the first three stay resident. #}
{% macro weight() -%}
    LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1
{%- endmacro %}
{% macro reduce_channel(next, branch='') %}
{% for j in range(tiles) %}
    MULT.RC.VV {{ slots[[j, 3] | min] }} R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ cr.full_ds }}.L {% if j == 0 %}; INC LR6 1{% endif %}
    {%- if tiles == 5 and j in [2, 3] %}; LD.MULT.CYCLIC {{ 'LR13' if j == 2 else 'LR14' }} {{ cr.in0 }} LR12
    {%- elif j + 1 < tiles or next %}; {{ weight() }}{% endif %}
    {%- if j + 1 == tiles and branch %}; {{ branch }}{% endif %} ;;
{% if tiles == 5 and j in [2, 3] %}
    {{ weight() }} ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro reduce_group(count, ds, tag) %}
{# Branch reads the old counter; on a multi-chunk dot it is already
   advanced by the time the last chunk branches. Peel the final channel
   so the pipelined load never crosses the end of the coefficient group. #}
    {{ weight() }} ; SET LR6 CR0 ; SUB LR7 LR0 CR1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ weight() }} ; DEC LR6 1 ; INC LR7 {{ [0, count - (2 if tiles == 1 else 1)] | max }} ;;
{% if count > 1 %}
{{ tag }}:
    {{ reduce_channel(true, 'BLT.S LR6 LR7 ' ~ tag) }}
{% endif %}
    {{ reduce_channel(false) }}
    {{ store(ds) }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR2 CR0 ;;
    DEC LR3 1 ; SUB LR8 LR0 CR1 ; SET LR1 CR0 ;;
{% if tiles > 1 %}
    INC LR1 128 ;;
    ADD LR11 LR1 LR1 ; SET LR13 CR0 ;;
    ADD LR12 LR11 LR1 ;;
{% if tiles == 5 %}
    INC LR13 3 ; SET LR14 CR0 ;;
    INC LR14 4 ;;
{% endif %}
{% endif %}
{% for j in range(tiles if tiles < 5 else 3) %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} {{ slots[j] }} {% if j %}; INC LR2 1{% endif %} ;;
{% endfor %}
{% if groups > 1 %}
    SET LR5 {{ cr.last }} ;;
reduce_full:
    {{ reduce_group(128, cr.full_ds, 'reduce_full_channel') }}
    DEC LR5 1 ; BNE LR5 CR1 reduce_full ;;
{% endif %}
    {{ reduce_group(n - (groups - 1) * 128, cr.tail_ds, 'reduce_tail_channel') }}
    HALT ;;
{% else %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    DEC LR3 1 ; SET LR1 CR0 ;;
    INC LR1 128 ;;
{% if m == 1 and in0_d0 * in0_d2 * in0_d3 == 1 and k == in0_d1 and k <= 4096 %}
{# Channel dot products: keep up to four input chunks in the ring.
   For longer vectors keep three resident and stream through slot 3. #}
{% set tiles = (k + 127) // 128 %}
{% set resident = tiles if tiles <= 4 else 3 %}
{% set groups = (n + 127) // 128 %}
{% macro read_coeff() -%}
LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1
{%- endmacro %}
{% macro dot_body(count, ds, tag) %}
    {{ read_coeff() }} ; SET LR6 CR0 ; SET LR7 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; DEC LR6 1 ; INC LR7 {{ count - 1 }} ;;
{{ tag }}:
    {{ read_coeff() }} ; SET LR2 CR0 {% if tiles == 1 %}; INC LR6 1{% endif %} ;;
{% for j in range(tiles) %}
{% set slot = ['LR0', 'LR1', 'LR11', 'LR12'][[j, 3] | min] %}
    MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ cr.full_ds }}.L {% if j == 0 and tiles > 1 %}; INC LR6 1{% endif %} {% if j + 1 == tiles %}; BLT.S LR6 LR7 {{ tag }}{% elif j + 1 >= resident %}; INC LR2 {{ resident if j + 1 == resident else 1 }} ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR12{% else %}; {{ read_coeff() }}{% endif %} ;;
{% if resident <= j + 1 < tiles %}
    {{ read_coeff() }} ;;
{% endif %}
{% endfor %}
    {{ store(ds) }} ;;
{% endmacro %}
    SET LR11 LR1 ; SET LR12 LR1 ; SUB LR8 LR0 CR1 ;;
    INC LR11 128 ; INC LR12 128 ; SET LR2 CR0 ;;
    INC LR12 128 ;;
{% for j in range(resident) %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} {{ ['LR0', 'LR1', 'LR11', 'LR12'][j] }} {% if j %}; INC LR2 1{% endif %} ;;
{% endfor %}
{% if groups > 1 %}
    SET LR5 {{ cr.last }} ;;
dot_full:
    {{ dot_body(128, cr.full_ds, 'dot_full_channel') }}
    DEC LR5 1 ; BNE LR5 CR1 dot_full ;;
{% endif %}
    {{ dot_body(n - (groups - 1) * 128, cr.tail_ds, 'dot_tail_channel') }}
    HALT ;;
{% elif k <= 32 and n <= 128 and in0_d1 <= 128 %}
{# Keep the bias resident and prefetch the next pixel while draining this one. #}
    SET LR2 CR0 ; SET LR5 CR0 ; SET LR9 CR0 ;;
    INC LR2 128 ; SET LR6 {{ cr.in_rows }} ; SET LR15 CR1 ;;
    LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR2 ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
{% set split = [k, 10] | min if k <= 16 else 0 %}
{% macro short_last(prefetch) %}
    {{ mac('LR9') }} {% if k > split %}; INC LR9 1{% endif %} ; {{ store(cr.tail_ds) }} {% if prefetch %}; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; B short_pixel{% endif %} ;;
{% endmacro %}
short_pixel:
    MULT.RC.VE LR2 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR8 CR1 ; SUB LR9 LR0 CR1 ; LD.MULT.CYCLIC LR15 {{ cr.coeff }} LR0 ; DEC LR6 1 {% if k == 1 and split == 0 %}; BEQ LR6 CR1 short_last_pixel{% endif %} ;;
{% for j in range(k) %}
{% if j < split %}
    {{ mac('LR9') }} ; INC LR9 1 ; {{ coeff_load() }} {% if j + 1 == k %}; BEQ LR6 CR0 short_last_pixel{% endif %} ;;
{% endif %}
{% if j + 1 < k %}
    {{ mac('LR9') }} {% if j >= split %}; INC LR9 1{% endif %} ; {{ coeff_load() }} {% if j + 2 == k and k > split %}; BEQ LR6 CR0 short_last_pixel{% endif %} ;;
{% endif %}
{% endfor %}
    {{ short_last(true) }}
short_last_pixel:
    {{ short_last(false) }}
    HALT ;;
{% else %}
pixel:
    SUB LR8 LR0 CR1 ; SET LR6 CR0 ;;
block:
    SUB LR2 LR5 CR1 ; SET LR7 {{ cr.k }} ; {{ coeff_load() }} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ;;
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; SET LR9 CR0 ; SUB LR10 LR1 CR1 ; BLT.S LR7 LR1 short_chunk ;;
load_high:
    {{ coeff_load() }} ;;
high:
    {{ mac('LR9') }} ; DEC LR7 1 ; BEQ LR9 LR10 chunk_end ;;
    INC LR9 1 ; {{ coeff_load() }} ; B high ;;
chunk_end:
    BNE LR7 CR0 chunk ;;
    BLT.S LR6 {{ cr.last }} store_full ;;
    {{ store(cr.tail_ds) }} ; ADD LR5 LR5 {{ cr.chunks }} ;;
    BLT.S LR5 {{ cr.in_rows }} pixel ;;
    HALT ;;
store_full:
    {{ store(cr.full_ds) }} ; INC LR6 1 ; B block ;;
short_chunk:
    SUB LR10 LR7 CR1 ; B load_high ;;
{% endif %}
{% endif %}
