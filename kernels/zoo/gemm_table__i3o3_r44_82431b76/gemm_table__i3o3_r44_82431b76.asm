{# Keep spatial pixels on lanes. Share a residual across each suffix pair.
   Reserve three cyclic slots for rows reused by every output channel;
   the fourth streams input and scratch rows. #}
{% set small = k <= 16 %}
{% set tight = 18 <= k <= 32 and k % 2 == 0 %}
{% set cached = small and k >= 13 %}
{% set compensated = not small %}
{% set groups = (k - 2) // 2 if tight else ([(k + 3) // 4, (k - 1) // 2] | min) if small else k // 4 if k <= 64 else (k - 1) // 2 %}
{% set paired = k - 2 * groups %}
{% macro coeff(reg) -%}
INC LR7 1 ; LD.MULT {{ reg }} LR7 {{ cr.coeff }}
{%- endmacro %}
{% macro input() -%}
LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{%- endmacro %}
{% macro next_input() -%}
ADD LR6 LR6 {{ cr.height }} ; {{ input() }}
{%- endmacro %}
{% macro mac(src, first=false, vec='LR0') -%}
MULT.RC.VE {{ vec }} {{ src }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro bias_mac(src, first=false) -%}
MULT.EE {{ src }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro finish() -%}
ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; {{ coeff('R0') }} ; DEC LR8 1 ; BNE LR8 CR1 channel
{%- endmacro %}
{% macro pairs(taps, more=false) %}
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1{% if loop.last and (groups or more) %} ; {{ coeff('R0') }}{% endif %} ;;
    {{ mac('LR2') }} ; INC LR2 1{% if not loop.last or (small and groups) %} ; {{ next_input() }}{% elif not more and not groups %} ; {{ finish() }}{% elif not more %} ; {{ coeff('R1') }} ; SET LR9 CR0{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro tail(count, more=false) %}
{% for j in range(count) %}
    {{ mac('LR1') }} ; {{ next_input() }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; LD.MULT.CYCLIC LR9 {{ cr.sums }} LR0 ; INC LR2 1 {% if loop.last and not more %}; ADD LR1 LR13 CR1{% endif %} ;;
    {% if loop.last and not more %}{{ mac('LR1') }} ; DEC LR13 {{ count - 1 }} ; {{ finish() }}{% else %}{{ mac('LR13') }} ; INC LR13 1 ; {% if loop.last %}{{ coeff('R0') }}{% else %}{{ next_input() }} ; INC LR9 1{% endif %}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro indices() -%}
SUB LR1 LR0 CR1 ; SET LR2 LR13
{%- endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
    SET LR4 CR0 ; SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.height }} ;;
    SET LR15 CR0 ; SET LR13 CR0 ;;
    INC LR15 255 ; INC LR13 127 ;;
{% if tight or cached %}
    SET LR14 CR1 ; SET LR9 CR1 ;;
    INC LR14 127 ; INC LR9 255 ;;
    {% if tight %}ADD LR9 LR9 LR14 ;;{% endif %}
{% endif %}
{% if tight %} ADD LR15 LR14 LR14 ;; {% endif %}
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
{% if tight %}
    {# Cache the first three input rows and stage one four-tap sum,
       followed by the remaining two-tap sums. #}
    SET LR6 LR5 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR14 ;;
    ADD LR6 LR6 {{ cr.height }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR15 ;;
    ADD LR6 LR6 {{ cr.height }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR9 ;;
    SET LR2 CR0 ;;
    {{ input() }} ; DEC LR2 1 ;;
{% for j in range(groups) %}
    {% if loop.first %}
    {{ mac('CR1', true, 'LR14') }} ;;
    {{ mac('CR1', false, 'LR15') }} ;;
    {{ mac('CR1', false, 'LR9') }} ; {{ next_input() }} ;;
    {% else %}{{ mac('CR1', true) }} ; {{ next_input() }} ;;{% endif %}
    {{ mac('CR1') }} ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR2 ; INC LR2 1 {% if not loop.last %}; {{ next_input() }}{% endif %} ;;
{% endfor %}
{% elif cached %}
    {# Keep the first tap of each of the last three pairs resident so
       their coefficient loads do not interrupt the MAC stream. #}
    ADD LR6 LR5 {{ cr.cache_start }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR14 ; ADD LR2 LR9 LR14 ;;
    ADD LR6 LR6 {{ cr.height }} ;;
    ADD LR6 LR6 {{ cr.height }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR9 ;;
    ADD LR6 LR6 {{ cr.height }} ;;
    ADD LR6 LR6 {{ cr.height }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR2 ;;
{% endif %}
{% if compensated and groups and not tight %}
    SET LR6 LR5 ; SET LR9 CR0 ; SET LR1 CR0 ;;
{% if paired > 1 %}
    INC LR1 {{ (paired - 1) % 255 }} ;;
    {% for j in range((paired - 1) // 255) %} INC LR1 255 ;; {% endfor %}
skip_prefix:
    ADD LR6 LR6 {{ cr.height }} ; DEC LR1 1 ; BNE LR1 CR1 skip_prefix ;;
{% endif %}
    {{ input() }} ; ADD LR6 LR6 {{ cr.height }} ; SET LR1 {{ cr.cache_start }} ;;
stage_pair:
    {{ mac('CR1', true) }} ; {{ input() }} ; ADD LR6 LR6 {{ cr.height }} ;;
    {{ mac('CR1') }} ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR9 ; DEC LR1 1 ; BNE LR1 CR1 stage_next ;;
    B stage_done ;;
stage_next:
    {{ input() }} ; ADD LR6 LR6 {{ cr.height }} ; INC LR9 1 ; B stage_pair ;;
stage_done:
{% endif %}
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; SET LR3 LR12 ; LD.MULT R0 LR0 {{ cr.coeff }} ;;
channel:
{% if tight %}
    {{ bias_mac('LR13', true) }} ; {{ coeff('R1') }} ; ADD LR2 LR13 LR14 ; SET LR4 LR3 ;;
    {{ bias_mac('LR2') }} ; {{ coeff('R1') }} ; ADD LR3 LR3 {{ cr.height }} ; SET LR1 LR13 ;;
    {{ mac('LR1', false, 'LR14') }} ; INC LR1 1 ; {{ coeff('R0') }} ; ADD LR6 LR5 {{ cr.cache_start }} ;;
    {{ mac('LR1', false, 'LR15') }} ; INC LR1 1 ; SET LR14 CR0 ; SUB LR2 LR0 CR1 ;;
{% for j in range(groups) %}
    {{ mac('LR1', false, 'LR9' if loop.first else 'LR0') }} ; INC LR1 1 ; {{ next_input() }} ;;
    {{ mac('LR1') }} ; INC LR1 1 ; LD.MULT.CYCLIC LR14 {{ cr.sums }} LR0 {% if loop.last %}; INC LR2 1{% endif %} ;;
    {% if loop.last %}{{ mac('LR2') }} ; {{ finish() }} ; SET LR14 {{ cr.cache_slot }}{% else %}{{ mac('LR2') }} ; INC LR2 1 ; INC LR14 1 ; {{ next_input() }}{% endif %} ;;
{% endfor %}
{% else %}
    {{ bias_mac('LR13', true) }} ; {{ coeff('R1') }} ; SET LR6 LR5 ; SET LR4 LR3 ;;
{% if k > 32 %}
    {{ bias_mac('LR15') }} ; {{ coeff('R0') }} ; ADD LR3 LR3 {{ cr.height }} ;;
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ input() }} {% if paired > 32 %}; SET LR14 CR0{% endif %} ;;
{% else %}
    {{ bias_mac('LR15') }} ; {{ input() }} ; ADD LR3 LR3 {{ cr.height }} ; {{ indices() }} ;;
{% endif %}
{% if paired > 32 %}
    INC LR14 {{ (paired - 1) // 32 }} ;;
full_block:
    {{ pairs(32, true) }}
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ next_input() }} ; DEC LR14 1 ; BNE LR14 CR1 full_block ;;
{% endif %}
    {{ pairs((paired - 1) % 32 + 1) }}
{% if small and groups %}
{% for j in range(groups) %}
    {{ mac('LR0', false, ['LR0', 'LR14', 'LR9', 'LR2'][j] if cached else 'LR0') }} ; {{ next_input() }} ;;
    {{ mac('LR13') }} ; {% if loop.last %}{{ finish() }}{% else %}{{ coeff('R0') }}{% if cached %} ; ADD LR6 LR6 {{ cr.height }}{% if loop.index == 1 %} ; SET LR2 {{ cr.cache_slot }}{% endif %}{% endif %}{% endif %} ;;
    {% if not loop.last and not cached %}{{ next_input() }} ;;{% endif %}
{% endfor %}
{% elif groups %}
    {{ next_input() }} ; SUB LR1 LR0 CR1 ; DEC LR2 {{ 65 + (paired - 1) % 32 }} ;;
{% if groups > 32 %}
    SET LR14 CR0 ;;
    INC LR14 {{ (groups - 1) // 32 }} ;;
tail_block:
    {{ tail(32, true) }}
    {{ coeff('R1') }} ; SUB LR1 LR0 CR1 ; DEC LR2 32 ;;
    DEC LR13 32 ;;
    {{ next_input() }} ; INC LR9 1 ; DEC LR14 1 ; BNE LR14 CR1 tail_block ;;
{% endif %}
    {{ tail((groups - 1) % 32 + 1) }}
{% endif %}
{% endif %}
    INC LR5 1 ; DEC LR10 1 ; DEC LR11 1 ;;
    INC LR12 1 ; BEQ LR10 CR0 end ;;
    BNE LR11 CR0 stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; ADD LR12 LR4 CR1 ; SET LR11 {{ cr.height }} ; B stripe ;;
end:
    HALT ;;
