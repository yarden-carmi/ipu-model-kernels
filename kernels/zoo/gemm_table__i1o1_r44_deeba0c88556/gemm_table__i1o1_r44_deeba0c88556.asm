{% set packed = in0_d1 <= 64 %}
{% set medium = 32 < k and k < 128 and k % 32 == 0 and n > 128 and n % 128 == 0 and m % 2 == 0 %}
{% set period = 32 if medium else 16 if m > 1 else 1 %}
{% set tail = 1 + (k - 1) % 128 %}
{% set remainder = 1 + (tail - 1) % period %}
{% set pipeline = medium %}
{% macro next_coeff() -%}
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, mode='ADD') -%}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro store(ds) -%}
    INC LR2 1 ; ACTIVATE.QUANTIZE {{ 'generic' if act_out0 in ['silu', 'hardswish', 'hardsigmoid'] else act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
{% macro channel(i, advance=true, prefetch=true) -%}
    {% if m > 1 and i % 16 >= (7 if k > 32 else 2 if n < 128 else 0) %}{{ mac('LR5') }} ; {{ next_coeff() }} ;;{% endif %}
    {% if advance %}{{ mac('LR7') }} ; SET LR7 LR5 ; INC LR5 1{% else %}{{ mac('LR5') }}{% endif %}
    {% if prefetch %}; {{ next_coeff() }}{% endif %}
{%- endmacro %}
{% macro group(limit, label) -%}
{{ label }}:
{% for i in range(period) %}
    {{ channel(i) }} {% if loop.last %}; BNE LR5 {{ limit }} {{ label }}{% endif %} ;;
{% endfor %}
{%- endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR1 CR0 ; SET LR10 CR0 ; DEC LR2 1 ;;
    SET LR12 CR0 ;;
{% for i in range(5) %}
    {% if i %}INC LR1 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
{% endfor %}
{% if pipeline %}
    {# Stage x[j] + x[j+1] at lane j. Only the even tap lanes are read back;
       exclude the last lane, where the shifted read crosses the row. #}
    SET LR6 CR0 ; SET LR5 CR1 ; DEC LR8 1 ;;
    DEC LR6 1 ;;
pair_sum:
    INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ;;
    MULT.RC.VE LR5 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L {{ cr.pairs }} LR6 ; BNE LR6 LR8 pair_sum ;;
{% macro pair_tap(advance=true, prefetch=true) -%}
    {{ mac('LR7' if advance else 'LR5') }}{% if advance %} ; SET LR7 LR5 ; INC LR5 1{% endif %}{% if prefetch %} ; {{ next_coeff() }}{% endif %}
{%- endmacro %}
{% macro slab(last=false) -%}
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ next_coeff() }} ; SET LR5 LR12 ; ADD LR11 LR12 {{ cr.preceding }} ;;
    {{ mac('CR1') }} ; {{ next_coeff() }} ; DEC LR9 1 ;;
{% for tile in range(k // 32) %}
{% set final_tile = loop.last %}
{% for i in range(32) %}
{# The first two pairs retain separate residuals. The other pairs use
   one residual multiplied by the staged sum of their inputs. #}
{% if i < 4 %}
    {{ mac('LR5') }} ; {{ next_coeff() }}{% if i % 2 %} ; INC LR11 2{% endif %} ;;
{% elif i % 2 == 0 %}
    {{ mac('LR7') }} ; SET LR7 LR11 ; {{ next_coeff() }} ; INC LR11 2 ;;
{% endif %}
{% if final_tile and loop.last %}
{% if last %}
    {{ pair_tap(false, false) }} ; {{ store(cr.full_ds) }} ; SET LR4 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ; DEC LR14 1 ;;
{% else %}
    {{ pair_tap(false) }} ; {{ store(cr.full_ds) }} ; BNE LR9 CR1 middle_slab ;;
{% endif %}
{% else %}
    {{ pair_tap() }} ;;
{% endif %}
{% endfor %}
{% endfor %}
{%- endmacro %}
    SET LR4 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
pipe_pixel:
    LD.MULT R0 LR3 {{ cr.in0 }} ; SET LR9 {{ cr.blocks }} ;;
    LD.MULT R1 LR3 {{ cr.pairs }} ;;
middle_slab:
    {{ slab() }}
    {{ slab(true) }}
{% if packed %}
    BNE LR12 CR0 pipe_second ;;
    SET LR12 LR15 ; B pipe_pixel ;;
pipe_second:
    INC LR3 1 ; SET LR12 CR0 ; BNE LR14 CR0 pipe_pixel ;;
{% else %}
    INC LR3 1 ; BNE LR14 CR0 pipe_pixel ;;
{% endif %}
    HALT ;;
{% elif packed and k <= 32 and n <= 128 and m > 1 %}
{% macro packed_pixel(start, second=false) -%}
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ next_coeff() }} ; SET LR5 {{ start }} ;;
    {{ mac('CR1') }} ; {{ next_coeff() }} ; DEC LR14 1 ;;
{% for i in range(k - 1) %}
    {{ channel(i % period) }} ;;
{% endfor %}
    {{ channel((k - 1) % period, false, false) }} ; {{ store(cr.tail_ds) }} ; SET LR4 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ; {% if second %}INC LR3 1 ; BNE LR14 CR0 packed_pair{% else %}BEQ LR14 CR0 finish{% endif %} ;;
{%- endmacro %}
    SET LR4 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
packed_pair:
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
    {{ packed_pixel('CR0') }}
    {{ packed_pixel('LR15', true) }}
finish:
    HALT ;;
{% else %}
{% if k > 128 %}
    INC LR10 127 ;;
{% endif %}
pixel:
    SET LR4 CR0 ; SET LR9 {{ cr.blocks }} ; DEC LR14 1 ;;
    DEC LR4 1 ; ADD LR13 LR12 {{ cr.before_last }} ;;
block:
    {{ next_coeff() }} ; SET LR6 LR3 ; DEC LR9 1 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ next_coeff() }} ; SET LR8 {{ cr.preceding }} ;;
{% if m > 1 %}
    {{ mac('CR1') }} ; {{ next_coeff() }} ;;
{% endif %}
{% if k > 128 %}
full_chunk:
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR8 1 ; SET LR5 CR0 ;;
{{ group('LR10', 'full_scalar') }}
    INC LR6 1 ; BNE LR8 CR0 full_chunk ;;
{% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR5 LR12 ;;
{% if tail > period %}
{{ group('LR13', 'tail_scalar') }}
{% endif %}
{% for i in range(remainder - 1) %}
    {{ channel(i) }} ;;
{% endfor %}
{% if n > 128 and n % 128 %}
    {{ channel(remainder - 1, false, false) }} ; BNE LR9 CR0 full_store ;;
    {{ store(cr.tail_ds) }} ;;
{% else %}
    {{ channel(remainder - 1, false, false) }} ; {{ store(cr.tail_ds) }} ; BNE LR9 CR0 block ;;
{% endif %}
    BEQ LR14 CR0 finish ;;
{% if packed %}
    BEQ LR12 CR0 second_pixel ;;
    SET LR12 CR0 ; INC LR3 1 ; B pixel ;;
second_pixel:
    SET LR12 LR15 ; B pixel ;;
{% else %}
    ADD LR3 LR3 {{ cr.chunks }} ; B pixel ;;
{% endif %}
finish:
    HALT ;;
{% if n > 128 and n % 128 %}
full_store:
    {{ store(cr.full_ds) }} ; B block ;;
{% endif %}
{% endif %}
