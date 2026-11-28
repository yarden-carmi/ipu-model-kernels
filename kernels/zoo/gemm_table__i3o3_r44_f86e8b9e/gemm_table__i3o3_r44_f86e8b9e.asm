{# Input rows run channel-first within a stripe; output channels stride by height. #}
{% if k == 16 and n == 64 %}
{% macro product(slot, scalar, first=false) -%}
MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
    SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.out0_d2 }} ; SET LR13 CR0 ;;
    INC LR13 127 ; SET LR4 CR0 ; SET LR14 CR0 ;;
    INC LR14 128 ; SET LR15 CR0 ;;
    ADD LR15 LR14 LR14 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe_fast:
    SET LR6 LR5 ; SUB LR9 LR0 CR1 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR14 ;;
{# Keep the first two input vectors resident across the output-channel loop. #}
{% set groups = [2, 2, 3, 3, 3, 3] %}
{% for count in groups %}
{% set first_group = loop.first %}
{% set last_group = loop.last %}
{% for j in range(count) %}
    {{ product(('LR14' if j == 0 else 'LR15') if first_group else 'LR0', 'CR1', loop.first) }}{% if loop.last %} ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR9 ; INC LR9 1{% endif %}{% if not (loop.last and last_group) %} ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} {{ 'LR15' if first_group and j == 0 else 'LR0' }}{% endif %} ;;
{% endfor %}
{% endfor %}
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; SUB LR4 LR12 {{ cr.out0_d2 }} ; LD.MULT R0 LR0 {{ cr.coeff }} ;;
channel_fast:
    MULT.EE LR13 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ; SET LR6 LR5 ; SET LR2 LR13 ;;
    {{ product('LR14', 'LR0') }} ; INC LR7 1 ; LD.MULT R1 LR7 {{ cr.coeff }} ; SET LR1 CR0 ; ADD LR4 LR4 {{ cr.out0_d2 }} ;;
    {{ product('LR15', 'LR1') }} ; INC LR1 1 ; INC LR6 1 ; SET LR9 CR0 ; LD.MULT.CYCLIC LR9 {{ cr.sums }} LR0 ;;
{% for count in groups %}
{% if not loop.first %}
{% for j in range(count) %}
    {{ product('LR0', 'LR1') }} ; INC LR1 1{% if loop.last %} ; LD.MULT.CYCLIC LR9 {{ cr.sums }} LR0 ; INC LR9 1{% else %} ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %} ;;
{% endfor %}
{% endif %}
    {{ product('LR0', 'LR2') }} ; INC LR2 1{% if not loop.last %} ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% else %} ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ; DEC LR8 1 ; BNE LR8 CR1 channel_fast{% endif %} ;;
{% endfor %}
    ADD LR5 LR5 {{ cr.k }} ; INC LR12 1 ; DEC LR10 1 ;;
    DEC LR11 1 ; BNE LR11 CR1 stripe_fast ;;
    BEQ LR10 CR0 end_fast ;;
    ADD LR12 LR12 {{ cr.output_skip }} ; SET LR11 {{ cr.out0_d2 }} ; B stripe_fast ;;
end_fast:
    HALT ;;
{% else %}
{% macro load_coeff(reg) -%}
INC LR7 1 ; LD.MULT {{ reg }} LR7 {{ cr.coeff }}
{%- endmacro %}
{% macro load_input() -%}
INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{%- endmacro %}
{% macro mac(index) -%}
MULT.RC.VE LR0 {{ index }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
{% macro taps(count, final, advance=false) %}
{% if k == 16 %}
    {{ load_input() }} ; SUB LR1 LR0 CR1 ; SET LR2 LR13 ;;
{% else %}
    {{ load_coeff('R0') }} ; SUB LR1 LR0 CR1 ; SET LR2 LR13 ;;
    {{ load_coeff('R1') }} ;;
    {{ load_input() }} ;;
{% endif %}
{% for tap in range(count) %}
{% if k == 16 and tap >= 12 %}
    {{ mac('LR1') }} ; INC LR1 1{% if advance and tap == 14 %} ; ADD LR3 LR3 {{ cr.out0_d2 }}{% else %} ; INC LR2 1{% endif %}{% if not loop.last %} ; {{ load_input() }}{% elif final %} ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4{% endif %} ;;
{% else %}
    {{ mac('LR1') }} ; INC LR1 1{% if k == 16 and tap == 0 %} ; {{ load_coeff('R1') }}{% endif %} ;;
    {{ mac('LR2') }} ; INC LR2 1{% if not loop.last %} ; {{ load_input() }}{% elif final %} ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4{% endif %} ;;
{% endif %}
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.out0_d2 }} ; SET LR13 CR0 ;;
    INC LR13 127 ; SET LR12 CR0 ; SET LR15 CR0 ;;
    INC LR15 128 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
    {% if k == 16 and n == 64 %}SET LR8 CR0{% else %}SET LR8 {{ cr.n }}{% endif %} ; SUB LR7 LR0 CR1 ; SET LR3 LR12 ;;
{% if k == 16 and n == 64 %}    INC LR8 16 ;;
{% endif %}
channel:
{% macro channel_body(advance=false) %}
{% if k == 16 %}
    {{ load_coeff('R0') }} ; SUB LR6 LR5 CR1 ; SET LR4 LR3 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ load_coeff('R0') }} ;;
{% else %}
    {{ load_coeff('R0') }} ; SUB LR6 LR5 CR1 ; SET LR14 {{ cr.full_blocks }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ load_coeff('R1') }} ;;
    MULT.EE LR15 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR4 LR3{% if k == 16 %} ; {{ load_coeff('R0') }}{% endif %} ;;
{% endif %}
{% if k > 32 %}
block:
    {{ taps(32, false) }}
    DEC LR14 1 ; BNE LR14 CR1 block ;;
{% endif %}
    {{ taps((k - 1) % 32 + 1, true, advance) }}
{% if not advance %}
    ADD LR3 LR3 {{ cr.out0_d2 }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
{% endif %}
{% endmacro %}
{% if k == 16 and n == 64 %}
    {{ channel_body(true) }}
    {{ channel_body(true) }}
    {{ channel_body(true) }}
{% endif %}
    {{ channel_body() }}
    ADD LR5 LR5 {{ cr.k }} ; INC LR12 1 ; DEC LR10 1 ;;
    DEC LR11 1 ; BNE LR11 CR1 stripe ;;
    BEQ LR10 CR0 end ;;
    ADD LR12 LR12 {{ cr.output_skip }} ; SET LR11 {{ cr.out0_d2 }} ; B stripe ;;
end:
    HALT ;;
{% endif %}
