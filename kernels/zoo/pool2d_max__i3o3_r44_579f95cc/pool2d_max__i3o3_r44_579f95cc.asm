{% macro reduce(op, src, ds) %}
    MULT.VE {{ src }} CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; AGG.MAX{{ op }} LR8 {{ ds }}
{%- endmacro %}

{# Clamp a horizontal edge window. Seed only from an actual input lane. #}
{% macro edge(tag, seed) %}
{{ tag }}:
    SET LR9 LR7 ; ADD LR10 LR7 CR6.L ; BGE.S LR7 CR0 {{ tag }}_lo ;;
    SET LR9 CR0 ;;
{{ tag }}_lo:
    BLT.S LR10 CR6.H {{ tag }}_hi ;;
    SET LR10 CR6.H ;;
{{ tag }}_hi:
    DEC LR10 1 ;;
    {% if seed %}
    {{ reduce('.FIRST', 'LR9', 'CR9.H') }} ;;
    INC LR9 1 ; BGE.S LR9 LR10 {{ tag }}_next ;;
    {% endif %}
    DEC LR9 1 ; DEC LR10 1 ;;
{{ tag }}_tap:
    {{ reduce('', 'LR9', 'CR9.H') }} ; INC LR9 1 ; BLT.S LR9 LR10 {{ tag }}_tap ;;
{{ tag }}_next:
    INC LR8 1 ; ADD LR7 LR7 CR8.L ;;
{% endmacro %}

{# Scan one tap row. The interior uses one horizontal reduction per output. #}
{% macro scan(tag, op, seed) %}
    LD.MULT R0 LR5 {{ cr.in0 }} ; SUB LR7 LR0 CR8.H ; SET LR8 CR0 ;;
    BEQ LR8 LR13 {{ tag }}_left_done ;;
    {{ edge(tag ~ '_left', seed) }}
    BLT.S LR8 LR13 {{ tag }}_left ;;
{{ tag }}_left_done:
    SET LR10 LR14 ;;
    INC LR10 2 ;;
    BGE.S LR8 LR10 {{ tag }}_middle_done ;;
    SUB LR7 LR7 CR8.L ; DEC LR8 1 ;;
{{ tag }}_middle:
    {{ reduce(op, 'LR7', 'CR9.L') }} ; ADD LR7 LR7 CR8.L ; INC LR8 1 ; BLT.S LR8 LR14 {{ tag }}_middle ;;
    ADD LR7 LR7 CR8.L ; INC LR8 1 ;;
{{ tag }}_middle_done:
    BGE.S LR8 CR7.L {{ tag }}_right_done ;;
    {{ edge(tag ~ '_right', seed) }}
    BLT.S LR8 CR7.L {{ tag }}_right ;;
{{ tag }}_right_done:
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
batch:
    SUB LR12 LR1 CR13 ; SET LR3 CR0 ;;
output_y:
    SET LR4 LR12 ; ADD LR6 LR12 CR14 ; ADD LR5 LR1 CR15 ;;
    BGE.S LR4 LR1 ylo ;;
    SET LR4 LR1 ;;
ylo:
    BLT.S LR6 LR5 yhi ;;
    SET LR6 LR5 ;;
yhi:
    SET LR11 CR0 ;;
channel:
    SET LR5 LR4 ;;
    {{ scan('seed', '.FIRST', true) }}
    ADD LR5 LR5 CR11 ;;
    BGE.S LR5 LR6 store ;;
tap_y:
    {{ scan('update', '', false) }}
    ADD LR5 LR5 CR11 ;;
    BLT.S LR5 LR6 tap_y ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR10.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR4 1 ; INC LR6 1 ;;
    INC LR2 1 ; INC LR11 1 ;;
    BLT.S LR11 CR11 channel ;;
    INC LR3 1 ; ADD LR12 LR12 CR12 ;;
    BLT.S LR3 CR7.H output_y ;;
    ADD LR1 LR1 CR15 ; DEC LR15 1 ;;
    BNE LR15 CR0 batch ;;
    HALT ;;
