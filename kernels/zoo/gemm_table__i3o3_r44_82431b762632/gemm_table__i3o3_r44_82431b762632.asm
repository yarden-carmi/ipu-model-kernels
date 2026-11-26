{# A stripe is one physical row of spatial positions, across all channels. #}
{% macro coeff(reg) -%}
INC LR7 1 ; LD.MULT {{ reg }} LR7 {{ cr.coeff }}
{%- endmacro %}
{% macro input() -%}
LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{%- endmacro %}
{% macro mac(index) -%}
MULT.RC.VE LR0 {{ index }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
{% set shared = k > 32 and k % 2 == 0 %}
{% macro shared_taps(count, final) %}
    {{ coeff('R0') }} ; SUB LR1 LR0 CR1 ; SET LR2 LR13 ;;
    SET LR10 LR6 ; LD.MULT.CYCLIC LR10 {{ cr.sums }} LR15 ;;
{% for j in range(count // 2) %}
    {{ mac('LR1') }} ; INC LR1 1 ; ADD LR6 LR10 {{ cr.height }} ; {% if loop.first %}{{ coeff('R1') }}{% else %}LD.MULT.CYCLIC LR10 {{ cr.sums }} LR15{% endif %} ;;
    MULT.RC.VE LR15 LR2 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR2 1 ; {{ input() }} ;;
    {{ mac('LR1') }} ; INC LR1 1{% if loop.last and final %} ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; DEC LR8 1 ; BNE LR8 CR1 channel{% elif loop.last %} ; ADD LR6 LR6 {{ cr.height }} ; {{ input() }} ; DEC LR14 1 ; BNE LR14 CR1 block{% else %} ; ADD LR10 LR6 {{ cr.height }} ; LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro taps(count, final) %}
    {{ coeff('R0') }} ; SUB LR1 LR0 CR1 ; SET LR2 LR13 ;;
{% for j in range(count) %}
    {{ mac('LR1') }} ; INC LR1 1{% if loop.first %} ; {{ coeff('R1') }}{% endif %} ;;
    {{ mac('LR2') }} ; INC LR2 1{% if not loop.last %} ; ADD LR6 LR6 {{ cr.height }} ; {{ input() }}{% elif final %} ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; DEC LR8 1 ; BNE LR8 CR1 channel{% else %} ; ADD LR6 LR6 {{ cr.height }} ; {{ input() }} ; DEC LR14 1 ; BNE LR14 CR1 block{% endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR11 {{ cr.height }} ; SET LR13 CR0 ;;
    INC LR13 127 ; SET LR12 CR0 ; SET LR15 CR0 ;;
    INC LR15 128 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
{% if shared %}
    SET LR6 LR5 ; SET LR14 LR9 ; {{ input() }} ;;
stage_pair:
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR10 LR6 ; ADD LR6 LR6 {{ cr.height }} ; {{ input() }} ;;
    {{ mac('CR1') }} ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR10 ; DEC LR14 1 ; BEQ LR14 CR1 staged ;;
    ADD LR6 LR6 {{ cr.height }} ; {{ input() }} ; B stage_pair ;;
staged:
{% endif %}
    SET LR8 {{ cr.n }} ; SUB LR7 LR0 CR1 ; SET LR3 LR12 ;;
channel:
    {{ coeff('R0') }} ; SET LR6 LR5 ; SET LR14 {{ cr.full_blocks }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ coeff('R1') }} ; SET LR4 LR3 ;;
    MULT.EE LR15 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR3 LR3 {{ cr.height }} ; {{ input() }} ;;
{% if k > 32 %}
block:
    {% if shared %}{{ shared_taps(32, false) }}{% else %}{{ taps(32, false) }}{% endif %}
{% endif %}
    {% if shared %}{{ shared_taps((k - 1) % 32 + 1, true) }}{% else %}{{ taps((k - 1) % 32 + 1, true) }}{% endif %}
    INC LR5 1 ; INC LR12 1 ;;
    DEC LR11 1 ; BNE LR11 CR1 stripe ;;
    BEQ LR5 {{ cr.stripe_end }} end ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; ADD LR12 LR12 {{ cr.output_skip }} ; SET LR11 {{ cr.height }} ; B stripe ;;
end:
    HALT ;;
