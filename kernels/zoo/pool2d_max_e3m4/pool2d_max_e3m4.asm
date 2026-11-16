    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR3 CR0 ;;
    SET LR6 CR0 ;;
row_loop:
    SET LR2 CR0 ;;
col_loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds_channels }}.L {{ cr.qf }}.L ; ACC.MAX.FIRST ;;
{% for dy in [0, 1] %}
{% for dx in [0, 1] %}
{% if dy != 0 or dx != 0 %}
{% if dy == 0 %}
    SET LR5 LR1 ;;
{% else %}
    ADD LR5 LR1 {{ cr.w }} ;;
{% endif %}
{% if dx == 1 %}
    INC LR5 1 ;;
{% endif %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds_channels }}.L {{ cr.qf }}.L ; ACC.MAX ;;
{% endif %}
{% endfor %}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.ds_channels }}.L {{ cr.qf }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ;;
    INC LR1 1 ;;
    INC LR2 1 ;;
    BNE LR2 {{ cr.ow }} col_loop ;;
    INC LR1 1 ;;
    INC LR3 1 ;;
    BNE LR3 {{ cr.oh }} row_loop ;;
    HALT ;;
