{% set half = m % 128 != 0 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro store(fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
{# LR7 walks packed NCHW channel rows for this spatial tile.
   With a half row of padding elided, odd channels start 64 lanes into a row. #}
{% macro mac(odd) %}
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 {% if odd %}; ADD LR11 LR7 LR14{% endif %} ;;
{% if odd %}
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR5 ;;
{% endif %}
    MULT.RC.VE {{ 'LR4' if odd else 'LR0' }} LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR12 LR9 LR5 ; ADD LR7 LR7 {{ 'LR15' if odd else cr.low }} ;;
    MULT.RC.VE {{ 'LR4' if odd else 'LR0' }} LR12 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1 ;;
{% endmacro %}
{% macro chunk(count, label) %}
    LD.MULT R0 LR8 {{ cr.w }} ; SET LR9 CR0 ; SET LR10 CR0 ;;
    INC LR10 {{ count // 8 }} ; INC LR8 1 ;;
    LD.MULT R1 LR8 {{ cr.w }} ;;
    INC LR8 1 ;;
{{ label }}:
{% for i in range(8) %}
    {{ mac(half and i % 2 == 1) }}
{% endfor %}
    DEC LR10 1 ;;
    BNE LR10 CR0 {{ label }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
{% if act == 'generic' %}
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
    INC LR2 1 ;;
{% endfor %}
{% endif %}
copy_channel:
    SET LR6 CR0 ;;
copy_tile:
    LD.MULT.CYCLIC LR1 {{ cr.in1 }} LR0 ; INC LR6 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    BLT.S LR6 LR15 copy_full ;;
    {{ store('identity', cr.tail) }}
    BLT.S LR1 {{ cr.copy_rows }} copy_channel ;;
    BEQ LR0 CR0 gemm ;;
copy_full:
    {{ store('identity', cr.full) }}
    BEQ LR0 CR0 copy_tile ;;
gemm:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ;;
    INC LR5 128 ;;
{% if half %}
    INC LR4 64 ;;
{% endif %}
channel:
    SET LR6 CR0 ;;
tile:
    SET LR7 LR6 ; SET LR8 LR3 ;;
    INC LR6 1 ;;
{% if half %}
    SET LR14 CR0 ;;
    BLT.S LR6 LR15 crossed ;;
    BEQ LR0 CR0 init ;;
crossed:
    INC LR14 1 ;;
init:
{% endif %}
{% if bias %}
    LD.MULT R0 LR2 {{ cr.b }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR11 LR2 ;;
    INC LR11 1 ;;
    LD.MULT R1 LR11 {{ cr.b }} ;;
    MULT.EE LR5 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
{% if k > 128 %}
    SET LR13 CR0 ;;
    INC LR13 {{ (k - 1) // 128 }} ;;
full_chunk:
    {{ chunk(128, 'full_group') }}
    DEC LR13 1 ;;
    BNE LR13 CR0 full_chunk ;;
{% endif %}
    {{ chunk((k - 1) % 128 + 1, 'tail_group') }}
    BLT.S LR6 LR15 gemm_full ;;
    {{ store(act, cr.tail) }}
    SET LR3 LR8 ; INC LR2 2 ;;
    BLT.S LR1 {{ cr.out_rows }} channel ;;
    HALT ;;
gemm_full:
    {{ store(act, cr.full) }}
    BEQ LR0 CR0 tile ;;
