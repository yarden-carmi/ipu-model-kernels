{# Use small independently scaled coefficient groups for the single-digit taps. #}
{% set width = 8 %}
{% set grouped = k < 144 %}
{% set compensated = k <= 96 %}
{% set groups = ([26, k // 2, k * 7 // 16] | min) if compensated else ([k * 5 // 16, (k - 1) // 2] | min) %}
{% if 32 < k <= 64 %}{% set groups = k // 4 %}{% endif %}
{% set paired = k - 2 * groups %}
{% set quad = k >= 8 and k <= 16 and k % 4 == 0 %}
{% if k <= 16 %}
{% set groups = k // 2 %}
{% set paired = k % 2 %}
{% endif %}
{% set chunks = [3, 3, 3, 3, 2, 2] if k == 16 else ([4] * (k // 4) if quad else []) %}
{% if quad %}{% set groups = chunks | length %}{% set paired = 0 %}{% endif %}
{% macro coeff(reg) -%}
INC LR7 1 ; LD.MULT {{ reg }} LR7 {{ cr.coeff }}
{%- endmacro %}
{% macro input() -%}
LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{%- endmacro %}
{% macro next_input() -%}
ADD LR6 LR6 {{ cr.height }} ; {{ input() }}
{%- endmacro %}
{% macro mac(src) -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
{% macro bias_mac(src, first=false) -%}
MULT.EE {{ src }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro taps(count, last=false) %}
{% for j in range(count) %}
    {{ mac('LR1') }} ; INC LR1 1 ; {% if not loop.last %}{{ next_input() }}{% elif last %}ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; {{ coeff('R0') }} ; DEC LR8 1 ; BNE LR8 CR1 channel{% else %}{{ coeff('R0') }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro finish() -%}
ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; {{ coeff('R0') }} ; DEC LR8 1 ; BNE LR8 CR1 channel
{%- endmacro %}
{% macro pairs(count, more=false) %}
{% for j in range(count) %}
    {{ mac('LR1') }} ; INC LR1 1{% if loop.last and (more or paired < k) %} ; {{ coeff('R0') }}{% endif %} ;;
    {{ mac('LR2') }} ; INC LR2 1{% if not loop.last %} ; {{ next_input() }}{% elif not more and paired == k %} ; {{ finish() }}{% elif not more and compensated %} ; {{ coeff('R1') }} ; SET LR9 LR13{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro indices() -%}
SUB LR1 LR0 CR1 ; SET LR2 LR13
{%- endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
    SET LR4 CR0 ; SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.height }} ;;
    SET LR13 CR0 ; SET LR15 CR0 ;;
    INC LR13 127 ; INC LR15 255 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
{% if compensated and groups %}
    SET LR6 LR5 ; SET LR9 CR0 ; SET LR1 CR0 ;;
    INC LR9 128 ;;
{% if paired %}
    INC LR1 {{ paired }} ;;
skip_prefix:
    ADD LR6 LR6 {{ cr.height }} ; DEC LR1 1 ; BNE LR1 CR1 skip_prefix ;;
{% endif %}
{% if quad %}
    {{ input() }} ;;
{% for chunk in chunks %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ next_input() }}{% if not loop.first %} ; INC LR9 1{% endif %} ;;
{% for j in range(chunk - 2) %}
    {{ mac('CR1') }} ; {{ next_input() }} ;;
{% endfor %}
    {{ mac('CR1') }} ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR9{% if not loop.last %} ; {{ next_input() }}{% endif %} ;;
{% endfor %}
{% else %}
    {{ input() }} ; SET LR1 CR0 ;;
    INC LR1 {{ groups }} ;;
stage_pair:
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ next_input() }} ;;
    {{ mac('CR1') }} ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR9 ; DEC LR1 1 ; BEQ LR1 CR1 stage_done ;;
    {{ next_input() }} ; INC LR9 1 ; B stage_pair ;;
stage_done:
{% endif %}
{% if not paired %}
    SET LR9 LR13 ; SET LR14 LR13 ;;
    INC LR14 {{ groups }} ;;
{% endif %}
{% endif %}
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; SET LR3 LR12 ; LD.MULT R0 LR0 {{ cr.coeff }} ;;
channel:
    {{ bias_mac('LR13', true) }} ; {{ coeff('R1') }} ; SET LR6 LR5 ; SET LR4 LR3 ;;
{% if grouped %}
{% if k > 64 or quad %}
    {{ bias_mac('LR15') }} ; {{ coeff('R0') }} ; ADD LR3 LR3 {{ cr.height }} ;;
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ input() }} ; {% if quad %}SUB LR1 LR0 CR1{% else %}SET LR14 CR0{% endif %} ;;
{% else %}
    {{ bias_mac('LR15') }} ; {{ input() }} ; ADD LR3 LR3 {{ cr.height }} ; {% if not paired %}SUB LR1 LR0 CR1 ; SET LR2 {{ cr.tail_b }}{% else %}{{ indices() }}{% endif %} ;;
{% endif %}
{% if paired > 32 %}
    INC LR14 {{ (paired - 1) // 32 }} ;;
pair_block:
    {{ pairs(32, true) }}
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ next_input() }} ; DEC LR14 1 ; BNE LR14 CR1 pair_block ;;
{% endif %}
{% if paired %}
    {{ pairs((paired - 1) % 32 + 1) }}
{% endif %}
{% if paired < k %}
{% if compensated %}
{% if paired %}
    {{ next_input() }} ; SUB LR1 LR0 CR1 ; SET LR2 {{ cr.tail_b }} ;;
{% endif %}
{% for j in range(groups) %}
{% if quad %}
{% for t in range(chunks[j] - 1) %}
    {{ mac('LR1') }} ; INC LR1 1 ; {{ next_input() }} ;;
{% endfor %}
    {{ mac('LR1') }} ; INC LR1 1 ; LD.MULT.CYCLIC LR9 {{ cr.sums }} LR0 ; INC LR9 1 ;;
{% else %}
    {{ mac('LR1') }} ; INC LR1 1 ; {{ next_input() }} ;;
    {{ mac('LR2') }} ; INC LR2 1 ; LD.MULT.CYCLIC LR9 {{ cr.sums }} LR0 ; INC LR9 1 ;;
{% endif %}
    {% if not paired and loop.last %}{{ mac('LR14') }} ; {{ finish() }} ; SET LR9 LR13{% else %}{{ mac('LR9') }} ; {% if loop.last %}{{ finish() }}{% else %}{{ next_input() }}{% endif %}{% endif %} ;;
{% endfor %}
{% elif groups <= 32 %}
    {{ next_input() }} ;;
{% for j in range(groups) %}
    {{ mac('LR0') }} ; {{ next_input() }} ;;
    {{ mac('LR13') }} ; {% if loop.last %}{{ finish() }}{% else %}{{ coeff('R0') }}{% endif %} ;;
    {% if not loop.last %}{{ next_input() }} ;;{% endif %}
{% endfor %}
{% else %}
    {{ next_input() }} ; SET LR14 CR0 ;;
    INC LR14 {{ groups }} ;;
single_pair:
    {{ mac('LR0') }} ; {{ next_input() }} ;;
    {{ mac('LR13') }} ; {{ coeff('R0') }} ; DEC LR14 1 ; BEQ LR14 CR1 group_store ;;
    {{ next_input() }} ; B single_pair ;;
group_store:
    ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
{% endif %}
{% endif %}
{% else %}
    {{ bias_mac('LR15') }} ; {{ coeff('R0') }} ; ADD LR3 LR3 {{ cr.height }} ;;
    {{ input() }} ; SUB LR1 LR0 CR1 ; SET LR14 CR0 ;;
    INC LR14 {{ (k - 1) // width }} ;;
{% if k > width %}
block:
    {{ taps(width) }}
    {{ next_input() }} ; SUB LR1 LR0 CR1 ; DEC LR14 1 ; BNE LR14 CR1 block ;;
{% endif %}
    {{ taps((k - 1) % width + 1, true) }}
{% endif %}
    INC LR5 1 ; DEC LR10 1 ; DEC LR11 1 ;;
    INC LR12 1 ; BEQ LR10 CR0 end ;;
    BNE LR11 CR0 stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; ADD LR12 LR12 {{ cr.output_skip }} ; SET LR11 {{ cr.height }} ; B stripe ;;
end:
    HALT ;;
