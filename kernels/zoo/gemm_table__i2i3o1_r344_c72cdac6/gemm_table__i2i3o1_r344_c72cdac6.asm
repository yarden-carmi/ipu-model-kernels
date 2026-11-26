{% set chunks = (in0_d2 + 127) // 128 %}
{% set shift = n % 128 %}
{% set tiles = (n + shift + 127) // 128 %}
{% set step = (m // in0_d2) * chunks %}
{% set rem = m % in0_d2 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}

{% macro fetch() %}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0{% endmacro %}
{% macro mac(src, mode='ADD') %}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro store(fn, ds, base=cr.out0, index='LR2') %}
ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ base }} {{ index }}
{%- endmacro %}
{% macro vec(mode) %}
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.{{ mode }}
{%- endmacro %}

# Each skip row supplies the scalar at x. Sliding across [zeros, 1, zeros]
# deposits that scalar in one channel lane of the output accumulator.
{% macro gather(tag, count, ds, base, index) %}
    SET LR14 CR0 ; SET LR10 CR0 ; LD.MULT R0 LR13 {{ cr.in1 }} ;;
    INC LR14 129 ; INC LR10 {{ count }} ;;
{% for mode in ['ADD.FIRST', 'ADD'] if count > 1 or mode == 'ADD.FIRST' %}
{% if mode == 'ADD' %}
{{ tag }}_channel:
    LD.MULT R0 LR13 {{ cr.in1 }} ;;
{% endif %}
    MULT.RC.VE LR14 LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.{{ mode }} ; INC LR13 1 ; DEC LR14 1 {% if count > 1 %}; DEC LR10 1{% endif %} {% if mode == 'ADD' %}; BNE LR10 CR1 {{ tag }}_channel{% endif %} ;;
{% endfor %}
    {{ store('identity', ds, base, index) }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR15 CR0 ;;
    INC LR15 {{ tiles }} ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
    INC LR0 1 ;;
{% endfor %}
    SET LR0 CR0 ;;
pixel:
    SET LR13 LR3 ; LD.MULT.CYCLIC LR0 {{ cr.unit }} LR0 ; SET LR11 CR1 ;;
    SET LR14 CR0 ;;
    INC LR14 128 ; LD.MULT.CYCLIC LR11 {{ cr.unit }} LR14 ;;
{% if n // 128 %}
    SET LR11 CR0 ;;
    INC LR11 {{ n // 128 }} ;;
skip_tile:
    {{ gather('full', 128, cr.full, cr.out0, 'LR2') }}
    INC LR2 1 ; DEC LR11 1 ; BNE LR11 CR1 skip_tile ;;
{% endif %}
{% if shift %}
    {{ gather('partial', shift, cr.skip_tail, cr.tmp, 'LR0') }}
{% endif %}
    SET LR4 CR0 ; SET LR11 CR0 ;;
    DEC LR4 1 ;;
gemm_tile:
    SET LR5 LR1 ; SET LR6 LR7 ; SET LR10 CR0 ;;
    INC LR10 {{ k }} ; INC LR11 1 ; {{ fetch() }} ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ fetch() }} ;;
    {{ mac('CR1') }} ; {{ fetch() }} ;;
channel:
{% if chunks == 2 %}
    ADD LR12 LR5 CR1 ; LD.MULT R1 LR12 {{ cr.in0 }} ;;
{% endif %}
    LD.MULT R0 LR5 {{ cr.in0 }} ; DEC LR10 1 {% if rem %}; SET LR12 LR6{% endif %} ;;
{% set src = 'LR12' if rem else 'LR6' %}
    {{ mac(src) }} ; {{ fetch() }} {% if rem %}; INC LR6 {{ rem }}{% endif %} ; BEQ LR10 CR0 last_channel ;;
    {{ mac(src) }} ; {{ fetch() }} {% if step %}; INC LR5 {{ step }}{% endif %} {% if rem %}; BLT.S LR6 {{ cr.in0_d2 }} channel{% else %}; B channel{% endif %} ;;
{% if rem %}
    SUB LR6 LR6 {{ cr.in0_d2 }} ; INC LR5 {{ chunks }} ; B channel ;;
{% endif %}
last_channel:
{% if shift %}
    BEQ LR11 CR1 merge_skip ;;
{% endif %}
    {{ mac(src) }} ; BEQ LR11 LR15 final_tile ;;
    {{ store(act, cr.full) }} ;;
    INC LR2 1 ; B gemm_tile ;;
final_tile:
    {{ store(act, cr.tail) }} ;;
next_pixel:
    INC LR2 1 ; INC LR7 1 ; DEC LR9 1 ; BEQ LR9 CR1 done ;;
    INC LR8 1 ; SET LR14 CR0 ;;
    INC LR14 {{ in1_d3 }} ;;
    BNE LR8 LR14 next_activation ;;
    SET LR8 CR0 ; INC LR3 {{ n }} ;;
next_activation:
    BNE LR7 {{ cr.in0_d2 }} pixel ;;
    SET LR7 CR0 ; INC LR1 {{ chunks }} ; B pixel ;;
done:
    HALT ;;

{% if shift %}
merge_skip:
    {{ mac(src) }} ; {{ store(act, cr.full, cr.tmp, 'LR11') }} ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
    {{ vec('ADD.FIRST') }} ; LD.MULT R0 LR11 {{ cr.tmp }} ;;
    {{ vec('ADD') }} ;;
{% if tiles == 1 %}
    {{ store('identity', cr.tail) }} ; B next_pixel ;;
{% else %}
    {{ store('identity', cr.full) }} ;;
    INC LR2 1 ; B gemm_tile ;;
{% endif %}
{% endif %}
