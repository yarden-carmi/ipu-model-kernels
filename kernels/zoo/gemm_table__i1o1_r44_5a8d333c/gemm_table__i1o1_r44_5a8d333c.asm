{% macro loadw() -%}
LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR0 ; INC LR7 1
{%- endmacro %}
{% set single = n <= 128 and k <= 128 %}
{% macro finish(phase) -%}
ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR4 1{% if single %} ; SET LR7 CR0 ; LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR0{% if phase == pack - 1 %} ; BNE LR10 CR0 pixel{% endif %}{% else %}{% if k <= 128 %} ; {{ loadw() }}{% endif %} ; BNE LR8 CR0 tile{{ phase }}{% endif %}
{%- endmacro %}
{% macro taps(count, last, phase) %}
{% for t in range(count) %}
    MULT.RC.VE LR0 LR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR1 1{% if not (last and loop.last) %} ; {{ loadw() }}{% else %} ; {{ finish(phase) }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro sums(count, last) %}
{% for i in range(count) %}
    MULT.RC.VE LR11 CR1 0 LR0 {{ cr.group_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR12 {{ cr.group_ds }}.L ; ADD LR11 LR11 {{ cr.group }} ; INC LR12 1{% if last and loop.last %} ; ACTIVATE.QUANTIZE identity {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR6 ; DEC LR13 1 ; BNE LR13 CR1 sum_pixel{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro grouped_taps(count, phase) %}
{% for i in range(count) %}
    MULT.RC.VE LR0 LR14 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR14 {{ group if sliding else 1 }} ; {{ loadw() }} ;;
    {{ taps(group, loop.last and k == groups * group, phase) }}
{% endfor %}
{% endmacro %}
{% macro grouped_blocks(phase) %}
{% for block in range(k // 16) %}
{% set used = (7 if block == 0 and groups == 13 else 6) if k <= 32 else 3 %}
{% set prev = (7 if block == 1 and groups == 13 else 6) if k <= 32 else 3 %}
{% for i in range(used) %}
    MULT.RC.VE LR0 LR14 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR14 {{ 5 + (i == 2)|int if k == 64 else 16 - (prev - 1) * group if block and loop.first else group }} ; {{ loadw() }} ;;
    {{ taps(group, k == 64 and loop.last and block == 3, phase) }}
    {% if k == 64 and i == 1 %}{{ taps(1, false, phase) }}{% endif %}
{% endfor %}
{% if k != 64 %}
    {{ taps(16 - used * group, loop.last, phase) }}
{% endif %}
{% endfor %}
{% endmacro %}
{% macro sliding_sum(next_pixel) %}
{% for i in range(group) %}
    {{ 'SET LR11 CR0' if loop.first else 'INC LR11 1' }} ; MULT.RC.VE LR11 CR1 0 LR0 {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L ; {{ 'ACC.ADD.FIRST' if loop.first else 'ACC.ADD' }}{% if loop.last %} ; INC LR12 1 ; ACTIVATE.QUANTIZE identity {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR12{% if next_pixel %} ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; BNE LR13 CR1 sum_pixel{% endif %}{% elif loop.first and next_pixel %} ; DEC LR13 1{% endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR10 {{ cr.input_sites }} ; SUB LR5 LR0 CR1 ; SUB LR4 LR0 CR1 ;;
    SET LR15 CR0 ;;
    INC LR15 {{ 128 - group if groups > 0 and sliding else 127 }} ;;
{% for segment in range(5) %}
    INC LR5 1 ; LD.LUT {{ segment }} {{ cr.lut }} LR5 ;;
{% endfor %}
    SUB LR5 LR0 CR1 ;;
{% if groups > 0 %}
{% if sliding %}
    SET LR6 CR0 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; SET LR13 {{ cr.input_sites }} ; SUB LR12 LR0 CR1 ;;
    BEQ LR13 CR1 last_sum ;;
sum_pixel:
    {{ sliding_sum(true) }}
last_sum:
    {{ sliding_sum(false) }}
{% else %}
    SUB LR6 LR0 CR1 ; SET LR13 {{ cr.input_sites }} ;;
sum_pixel:
    INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; SUB LR11 LR0 {{ cr.group }} ; SUB LR12 LR0 CR1 ;;
    {{ sums(groups, true) }}
{% endif %}
{% endif %}
{% macro dot_pixel(phase) %}
{% if single %}
    {% if phase == 0 %}INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; DEC LR10 1 ; {% endif %}MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SUB LR1 {{ 'LR3' if phase else 'LR0' }} CR1{% if phase %} ; {{ loadw() }} ; ADD LR14 LR15 LR3{% endif %} ;;
{% if groups > 0 and phase == 0 %}
    LD.MULT R1 LR5 {{ cr.sums }} ;;
{% endif %}
{% if phase == 0 %}
    {{ loadw() }} ; SET LR14 LR15 ;;
{% endif %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadw() }} ;;
{% else %}
    SUB LR7 LR0 CR1 ; SET LR8 {{ cr.tiles }}{% if phase == 0 %} ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }}{% endif %} ;;
{% if groups > 0 and phase == 0 %}
    LD.MULT R1 LR5 {{ cr.sums }} ;;
{% endif %}
{% if k <= 128 %}
    {{ loadw() }} ; SET LR6 LR5 ;;
{% endif %}
tile{{ phase }}:
{% if k > 128 %}
    {{ loadw() }} ; SET LR6 LR5 ; DEC LR8 1 ;;
{% endif %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ loadw() }} ; SUB LR1 {{ 'LR3' if phase else 'LR0' }} CR1{% if k <= 128 %} ; DEC LR8 1{% endif %} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadw() }} ; ADD LR14 LR15 {{ 'LR3' if phase else 'LR0' }} ;;
{% endif %}
{% if k > 128 %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 {{ cr.blocks }} ;;
{% endif %}
{% if k > 128 %}
chunk:
{% for part in range(4) %}
    {{ taps(32, false, phase) }}
{% endfor %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR6 1 ; SUB LR1 LR0 CR1 ; DEC LR9 1 ; BNE LR9 CR1 chunk ;;
{% endif %}
{% if groups > 0 %}
{% if k == 32 or k == 64 %}
    {{ grouped_blocks(phase) }}
{% else %}
    {{ grouped_taps(groups, phase) }}
    {% if k > groups * group %}{{ taps(k - groups * group, true, phase) }}{% endif %}
{% endif %}
{% else %}
{% set tail = (k - 1) % 128 + 1 %}
{% if split > 0 %}
{% for t in range(split) %}
    MULT.RC.VE LR0 LR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR1 1 ; {{ loadw() }} ;;
    MULT.RC.VE LR0 LR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if loop.last %} ; {{ finish(phase) }}{% else %} ; {{ loadw() }}{% endif %} ;;
{% endfor %}
{% else %}
{% for part in range((tail + 31) // 32) %}
    {{ taps([32, tail - 32 * part]|min, loop.last, phase) }}
{% endfor %}
{% endif %}
{% endif %}
{% if not single and phase == pack - 1 %}
    SET LR5 LR6 ; DEC LR10 1 ; BNE LR10 CR1 pixel ;;
{% endif %}
{% endmacro %}
{% if single %}
    SET LR7 CR0 ; LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR0 ;;
{% endif %}
pixel:
{% for phase in range(pack) %}
    {{ dot_pixel(phase) }}
{% endfor %}
    HALT ;;
