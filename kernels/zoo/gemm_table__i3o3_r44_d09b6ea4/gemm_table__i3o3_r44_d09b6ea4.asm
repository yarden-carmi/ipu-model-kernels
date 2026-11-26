{# Keep the packed spatial row on the lanes. Only the coefficient precision
   changes across the reduction: two digits, compensated groups, or small
   independently scaled rows. #}
{% set wide = k >= 144 %}
{% set compensated = k <= 96 %}
{% set quad = 8 <= k <= 16 and k % 4 == 0 %}
{% set chunks = [3, 3, 3, 3, 2, 2] if k == 16 else [4] * (k // 4) if quad else [] %}
{% set groups = chunks | length if quad else k // 2 if k <= 16 else k // 4 if 32 < k <= 64 else [26, k // 2, k * 7 // 16] | min if compensated else [k * 5 // 16, (k - 1) // 2] | min %}
{% set paired = 0 if quad else k - 2 * groups %}
{% set separate_bias = k > 64 or quad %}
{% macro coeff(reg) -%}INC LR7 1 ; LD.MULT {{ reg }} LR7 {{ cr.coeff }}{%- endmacro %}
{% macro input(next=false) -%}{% if next %}ADD LR6 LR6 {{ cr.height }} ; {% endif %}LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{%- endmacro %}
{% macro mac(src, first=false) -%}MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{%- endmacro %}
{% macro bias(src, first=false) -%}MULT.EE {{ src }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{%- endmacro %}
{% macro store() -%}ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4{%- endmacro %}
{% macro indices() -%}SUB LR1 LR0 CR1 ; SET LR2 LR13{%- endmacro %}
{% macro pairs(count) %}
{% for j in range(count) %}
    {{ mac('LR1') }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; INC LR2 1{% if not loop.last %} ; {{ input(true) }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro save_sum() -%}ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR9{%- endmacro %}

    SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.height }} ; INC LR13 127 ;;
    INC LR15 255 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
{% if compensated and groups %}
    SET LR6 LR5 ; SET LR9 LR13 ; SET LR1 CR0 ;;
    INC LR9 1 ;;
{% if paired %}
    INC LR1 {{ paired }} ;;
skip_prefix:
    ADD LR6 LR6 {{ cr.height }} ; DEC LR1 1 ; BNE LR1 CR1 skip_prefix ;;
{% endif %}
    {{ input() }} ;;
{% if quad %}
{% for chunk in chunks %}
    {{ mac('CR1', true) }} ; {{ input(true) }}{% if not loop.first %} ; INC LR9 1{% endif %} ;;
{% for j in range(chunk - 2) %}
    {{ mac('CR1') }} ; {{ input(true) }} ;;
{% endfor %}
    {{ mac('CR1') }} ; {{ save_sum() }}{% if not loop.last %} ; {{ input(true) }}{% endif %} ;;
{% endfor %}
{% else %}
    INC LR1 {{ groups }} ;;
stage_pair:
    {{ mac('CR1', true) }} ; {{ input(true) }} ;;
    {{ mac('CR1') }} ; {{ save_sum() }} ; DEC LR1 1 ; BEQ LR1 CR1 stage_done ;;
    {{ input(true) }} ; INC LR9 1 ; B stage_pair ;;
stage_done:
{% endif %}
{% endif %}
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; SET LR3 LR12 ; LD.MULT R0 LR0 {{ cr.coeff }} ;;
channel:
    {{ bias('LR13', true) }} ; {{ coeff('R1') }} ; SET LR6 LR5 ; SET LR4 LR3 ;;
    {{ bias('LR15') }} ; ADD LR3 LR3 {{ cr.height }}{% if separate_bias %} ; {{ coeff('R0') }}{% else %} ; {{ input() }}{% endif %} ;;
{% if separate_bias %}
    {{ coeff('R1') }} ;;
    {{ input() }} ; {{ indices() }} ;;
{% else %}
    {{ indices() }} ;;
{% endif %}
{% if wide %}
{% if k > 8 %}
    SET LR14 CR0 ;;
    INC LR14 {{ (k - 1) // 8 }} ;;
wide_block:
    {{ pairs(8) }}
    {{ coeff('R0') }} ; {{ indices() }} ;;
    {{ coeff('R1') }} ;;
    {{ input(true) }} ; DEC LR14 1 ; BNE LR14 CR1 wide_block ;;
{% endif %}
    {{ pairs((k - 1) % 8 + 1) }}
{% else %}
{% if paired > 32 %}
    SET LR14 CR0 ;;
    INC LR14 {{ (paired - 1) // 32 }} ;;
pair_block:
    {{ pairs(32) }}
    {{ coeff('R0') }} ; {{ indices() }} ;;
    {{ coeff('R1') }} ;;
    {{ input(true) }} ; DEC LR14 1 ; BNE LR14 CR1 pair_block ;;
{% endif %}
{% if paired %}
    {{ pairs((paired - 1) % 32 + 1) }}
{% endif %}
{% if groups and compensated %}
{% if paired %}
    {{ coeff('R0') }} ; SUB LR1 LR0 CR1 ;;
    {{ coeff('R1') }} ;;
    {{ input(true) }} ;;
{% endif %}
    SET LR9 LR13 ; SET LR2 {{ cr.tail_b }} ;;
{% for j in range(groups) %}
{% if quad %}
{% for t in range(chunks[j] - 1) %}
    {{ mac('LR1') }} ; INC LR1 1 ; {{ input(true) }} ;;
{% endfor %}
    {{ mac('LR1') }} ; INC LR1 1 ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.sums }} LR0 ;;
{% else %}
    {{ mac('LR1') }} ; INC LR1 1 ; INC LR2 1 ; {{ input(true) }} ;;
    {{ mac('LR2') }} ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.sums }} LR0 ;;
{% endif %}
    {{ mac('LR9') }}{% if not loop.last %} ; {{ input(true) }}{% endif %} ;;
{% endfor %}
{% elif groups %}
    {{ coeff('R0') }} ; SET LR14 CR0 ; SET LR1 LR13 ;;
    {{ input(true) }} ;;
    INC LR14 {{ groups }} ;;
single_pair:
    {{ mac('LR0') }} ; {{ input(true) }} ;;
    {{ mac('LR1') }} ; DEC LR14 1 ; BEQ LR14 CR1 finish ;;
    {{ coeff('R0') }} ;;
    {{ input(true) }} ; B single_pair ;;
{% endif %}
{% endif %}
finish:
    {{ store() }} ; {{ coeff('R0') }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    INC LR5 1 ; DEC LR10 1 ; DEC LR11 1 ;;
    INC LR12 1 ; BEQ LR10 CR0 end ;;
    BNE LR11 CR0 stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; ADD LR12 LR12 {{ cr.output_skip }} ; SET LR11 {{ cr.height }} ; B stripe ;;
end:
    HALT ;;
