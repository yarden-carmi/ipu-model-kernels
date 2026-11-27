{# One lane per spatial position; the original input rows stream directly. #}
{% macro input() %}LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endmacro %}
{% macro coeff(reg) %}INC LR7 1 ; LD.MULT {{ reg }} LR7 {{ cr.coeff }}{% endmacro %}
{% macro mac(index) %}MULT.RC.VE LR0 {{ index }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% endmacro %}
{% macro bias_mac(index, op) %}MULT.EE {{ index }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; {{ op }}{% endmacro %}
{% macro sum_mac(op) %}MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; {{ op }}{% endmacro %}
{% set lengths = [2] * 16 if k == 32 else [5, 5, 5, 5, 4, 4, 4] %}
{% macro shared_taps(final) %}
{% for j in range(32) %}
    {% set correction = (j % 2 == 1) if k == 32 else ((j < 20 and j % 5 == 4) or (j >= 20 and j % 4 == 3)) %}
    {{ mac('LR1') }} ; INC LR1 1 ; {% if not correction %}ADD LR6 LR6 {{ cr.plane }} ; {{ input() }}{% else %}LD.MULT.CYCLIC LR6 {{ cr.sums }} LR2{% endif %} {% if loop.first %}; INC LR7 1{% endif %} ;;
    {% if loop.first %}LD.MULT R1 LR7 {{ cr.coeff }} ;;{% endif %}
    {% if correction %}
    MULT.RC.VE LR2 LR9 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1 ; {% if not loop.last %}ADD LR6 LR6 {{ cr.plane }} ; {{ input() }}{% elif final %}ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; DEC LR8 1 ; BNE LR8 CR1 channel{% else %}{{ coeff('R0') }} ; DEC LR14 1 ; BNE LR14 CR1 block{% endif %} ;;
    {% endif %}
{% endfor %}
{% endmacro %}
{% macro taps(count, final) %}
{% for j in range(count) %}
    {{ mac('LR1') }} ; INC LR1 1 {% if loop.first %}; {{ coeff('R1') }}{% endif %} ;;
    {{ mac('LR9') }} ; INC LR9 1 ; {% if not loop.last %}ADD LR6 LR6 {{ cr.plane }} ; {{ input() }}{% elif final %}ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; DEC LR8 1 ; BNE LR8 CR1 channel{% else %}{{ coeff('R0') }} ; DEC LR14 1 ; BNE LR14 CR1 block{% endif %} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
    SET LR4 CR0 ; SET LR11 {{ cr.plane }} ; INC LR2 128 ;;
    SUB LR3 LR2 CR1 ;;
{% for i in range(5) %}
    {% if i %}INC LR4 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
{% if shared %}
    SET LR6 LR5 ; SET LR14 LR15 ; {{ input() }} ;;
stage_block:
{% for length in lengths %}
    {% set last_group = loop.last %}
    {% for j in range(length) %}
    {{ sum_mac('ACC.ADD.FIRST' if loop.first else 'ACC.ADD') }} ; {% if loop.last %}SET LR4 LR6 ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR4 ; {% endif %}{% if loop.last and last_group %}DEC LR14 1 ; BEQ LR14 CR1 staged{% else %}ADD LR6 LR6 {{ cr.plane }} ; {{ input() }}{% endif %} ;;
    {% endfor %}
{% endfor %}
    ADD LR6 LR6 {{ cr.plane }} ; {{ input() }} ; B stage_block ;;
staged:
{% endif %}
    SET LR8 {{ cr.n }} ; SUB LR7 LR0 CR1 ; SET LR13 LR12 ;;
channel:
    {{ coeff('R1') }} ; SET LR6 LR5 ; SET LR4 LR13 ;;
    {{ bias_mac('LR2', 'ACC.ADD.FIRST') }} ; {{ coeff('R1') }} ; ADD LR13 LR13 {{ cr.plane }} ; SET LR14 {{ cr.full_blocks }} ;;
    {{ bias_mac('LR2', 'ACC.ADD') }} ; {{ coeff('R0') }} ; SUB LR1 LR0 CR1 ; SET LR9 LR3 ;;
    {{ input() }} {% if k > 32 %}; B first_block{% endif %} ;;
{% if k > 32 %}
block:
    ADD LR6 LR6 {{ cr.plane }} ; {{ input() }} ; SUB LR1 LR0 CR1 ; SET LR9 LR3 ;;
first_block:
    {% if shared %}{{ shared_taps(false) }}{% else %}{{ taps(32, false) }}{% endif %}
    ADD LR6 LR6 {{ cr.plane }} ; {{ input() }} ; SUB LR1 LR0 CR1 ; SET LR9 LR3 ;;
{% endif %}
    {% if shared %}{{ shared_taps(true) }}{% else %}{{ taps((k - 1) % 32 + 1, true) }}{% endif %}
    INC LR5 1 ; INC LR12 1 ; DEC LR10 1 ; BEQ LR10 CR1 end ;;
    DEC LR11 1 ; BNE LR11 CR1 stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; ADD LR12 LR12 {{ cr.out_skip }} ; SET LR11 {{ cr.plane }} ; B stripe ;;
end:
    HALT ;;
