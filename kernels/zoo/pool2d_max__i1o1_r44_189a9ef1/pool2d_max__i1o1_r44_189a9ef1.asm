{% macro neighbor(dy, dx, n) %}
    SET LR7 LR3 ;;
    SET LR8 LR2 ;;
    {{ 'DEC' if dy < 0 else 'INC' }} LR7 {{ dy|abs }} ;;
    {{ 'DEC' if dx < 0 else 'INC' }} LR8 {{ dx|abs }} ;;
    BLT.S LR7 CR0 skip{{n}} ;;
    BGE.S LR7 {{ cr.h }} skip{{n}} ;;
    BLT.S LR8 CR0 skip{{n}} ;;
    BGE.S LR8 {{ cr.w }} skip{{n}} ;;
    SET LR5 LR1 ;;
{% if dy == -1 %}
    SUB LR5 LR5 {{ cr.w }} ;;
{% elif dy == 1 %}
    ADD LR5 LR5 {{ cr.w }} ;;
{% endif %}
    {{ 'DEC' if dx < 0 else 'INC' }} LR5 {{ dx|abs }} ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds_channels }}.L {{ cr.qf_in0 }}.L ; ACC.MAX ;;
skip{{n}}:
{% endmacro %}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR3 CR0 ;;
    SET LR6 CR0 ;;
row_loop:
    SET LR2 CR0 ;;
col_loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds_channels }}.L {{ cr.qf_in0 }}.L ; ACC.MAX.FIRST ;;
{% for dy, dx in [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)] %}
{{ neighbor(dy, dx, loop.index) }}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.ds_channels }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ;;
    INC LR1 2 ;;
    INC LR2 2 ;;
    BNE LR2 {{ cr.w }} col_loop ;;
    ADD LR1 LR1 {{ cr.w }} ;;
    INC LR3 2 ;;
    BNE LR3 {{ cr.h }} row_loop ;;
    HALT ;;
