{# Packed spatial stripes stay on the lanes. The prefix uses two coefficient
   digits; the suffix uses single digits and an affine correction on its sum. #}
{% set wide = in0_d2 * in0_d3 > 128 %}
{% set taps = (10 if k >= 48 else 4) if wide else 2 %}
{% set center = wide and k >= 48 %}
{% set groups = (k // 32 if center else (1 if 8 <= k <= 16 else 0)) if wide else [k * 5 // 16, (k - 1) // 2] | min %}
{% set paired = k - taps * groups %}
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
{% macro finish() -%}
ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; {{ coeff('R0') }} ; DEC LR8 1 ; BNE LR8 CR1 channel
{%- endmacro %}
{% macro pairs(taps, more=false) %}
{# The last coarse MAC can replace R0 while the last residual still uses R1. #}
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1{% if loop.last and (groups or more) %} ; {{ coeff('R0') }}{% endif %} ;;
    {{ mac('LR2') }} ; INC LR2 1{% if not loop.last %} ; {{ next_input() }}{% elif not groups and not more %} ; {{ finish() }}{% elif wide and not more %} ; SUB LR1 LR0 CR1 ; {{ next_input() }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro indices() -%}
SUB LR1 LR0 CR1 ; SET LR2 LR13
{%- endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
    SET LR4 CR0 ; SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.height }} ;;
    SET LR15 CR0 ; SET LR13 CR0 ;;
    INC LR15 255 ; INC LR13 127 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
{% if center %}
    {# Reuse the suffix input sum across the output channels of this stripe.
       Store its quantization residual separately to retain small sums. #}
    SET LR6 LR5 ; SET LR14 LR9 ; SET LR1 CR0 ;;
sum_seek:
    ADD LR6 LR6 {{ cr.height }} ; INC LR1 1 ; BLT.S LR1 {{ cr.seek }} sum_seek ;;
    {{ input() }} ;;
    MULT.RC.VE LR0 CR0 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
sum_group:
{% for j in range(taps) %}
    {{ mac('CR1') }}{% if not loop.last %} ; {{ next_input() }}{% endif %} ;;
{% endfor %}
    DEC LR14 1 ; BEQ LR14 CR1 sum_store ;;
    {{ next_input() }} ; B sum_group ;;
sum_store:
    ADD LR2 LR5 LR5 ;;
    ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR2 ;;
    LD.MULT.CYCLIC LR2 {{ cr.sums }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; INC LR2 1 ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR2 ;;
{% endif %}
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; SET LR3 LR12 ; LD.MULT R0 LR0 {{ cr.coeff }} ;;
channel:
    {{ bias_mac('LR13', true) }} ; {{ coeff('R1') }} ; SET LR6 LR5 ; SET LR4 LR3 ;;
{% if k > 32 %}
{% if center %}
    {{ bias_mac('LR15') }} ; {{ coeff('R0') }} ; ADD LR3 LR3 {{ cr.height }} ;;
    ADD LR2 LR5 LR5 ; LD.MULT.CYCLIC LR2 {{ cr.sums }} LR0 ;;
    {{ mac('LR0') }} ; INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.sums }} LR0 ;;
    {{ mac('LR0') }} ; {{ coeff('R0') }} ;;
{% else %}
    {{ bias_mac('LR15') }} ; {{ coeff('R0') }} ; ADD LR3 LR3 {{ cr.height }} ;;
{% endif %}
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ input() }} ; SET LR14 CR0 ;;
{% if paired > 32 %}
    INC LR14 {{ (paired - 1) // 32 }} ;;
{% endif %}
{% else %}
    {{ bias_mac('LR15') }} ; {{ input() }} ; ADD LR3 LR3 {{ cr.height }} ; {{ indices() }} ;;
{% endif %}
{% if paired > 32 %}
full_block:
    {{ pairs(32, true) }}
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ next_input() }} ; DEC LR14 1 ; BNE LR14 CR1 full_block ;;
{% endif %}
    {{ pairs((paired - 1) % 32 + 1) }}
{% if groups %}
{% if wide %}
{% macro tail(last=false) %}
{% for j in range(taps - 1) %}
    {{ mac('LR1') }} ; INC LR1 1 ; {{ next_input() }} ;;
{% endfor %}
    {{ mac('LR1') }} ; INC LR1 1 ; {% if last %}{{ finish() }}{% else %}{{ coeff('R0') }}{% endif %}
{%- endmacro %}
{% if groups <= 24 %}
{% for g in range(groups) %}
    {{ tail(loop.last) }} ;;
{% if not loop.last %}
    SUB LR1 LR0 CR1 ; {{ next_input() }} ;;
{% endif %}
{% endfor %}
{% else %}
    SET LR14 LR9 ;;
wide_group:
    {{ tail() }} ; DEC LR14 1 ; BEQ LR14 CR1 wide_store ;;
    SUB LR1 LR0 CR1 ; {{ next_input() }} ; B wide_group ;;
wide_store:
    ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
{% endif %}
{% elif groups <= 32 %}
    {{ next_input() }} ;;
{% for j in range(groups) %}
    {{ mac('LR0') }} ; {{ next_input() }} ;;
    {{ mac('LR13') }} ; {% if loop.last %}{{ finish() }}{% else %}{{ coeff('R0') }}{% endif %} ;;
    {% if not loop.last %}{{ next_input() }} ;;{% endif %}
{% endfor %}
{% else %}
    {{ next_input() }} ; SET LR14 LR9 ;;
single_pair:
    {{ mac('LR0') }} ; {{ next_input() }} ;;
    {{ mac('LR13') }} ; {{ coeff('R0') }} ; DEC LR14 1 ; BEQ LR14 CR1 store ;;
    {{ next_input() }} ; B single_pair ;;
store:
    ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
{% endif %}
{% endif %}
    INC LR5 1 ; DEC LR10 1 ; DEC LR11 1 ;;
    INC LR12 1 ; BEQ LR10 CR0 end ;;
    BNE LR11 CR0 stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; ADD LR12 LR12 {{ cr.output_skip }} ; SET LR11 {{ cr.height }} ; B stripe ;;
end:
    HALT ;;
