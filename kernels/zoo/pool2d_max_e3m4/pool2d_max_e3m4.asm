    SET LR0 CR0 ;;
    SET LR3 CR0 ;;
    SET LR4 CR0 ;;
    SET LR6 CR0 ;;
row_loop:
    SET LR1 LR4 ;;
    SET LR2 CR0 ;;
col_loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.MAX.FIRST ;;
{% for dy in [-1, 0, 1] %}
{% for dx in [-1, 0, 1] %}
{% if dy != 0 or dx != 0 %}
{% if dy == -1 %}
    BEQ LR3 CR0 skip_{{dy+1}}_{{dx+1}} ;;
{% endif %}
{% if dx == -1 %}
    BEQ LR2 CR0 skip_{{dy+1}}_{{dx+1}} ;;
{% endif %}
{% if dy == -1 %}
    SUB LR5 LR1 {{ cr.w }} ;;
{% elif dy == 1 %}
    ADD LR5 LR1 {{ cr.w }} ;;
{% else %}
    SET LR5 LR1 ;;
{% endif %}
{% if dx == -1 %}
    DEC LR5 1 ;;
{% elif dx == 1 %}
    INC LR5 1 ;;
{% endif %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.MAX ;;
skip_{{dy+1}}_{{dx+1}}:
{% endif %}
{% endfor %}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.ds_channels }}.L {{ cr.qf }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ;;
    INC LR1 2 ;;
    INC LR2 1 ;;
    BNE LR2 {{ cr.ow }} col_loop ;;
    ADD LR4 LR4 {{ cr.twow }} ;;
    INC LR3 1 ;;
    BNE LR3 {{ cr.oh }} row_loop ;;
    HALT ;;
