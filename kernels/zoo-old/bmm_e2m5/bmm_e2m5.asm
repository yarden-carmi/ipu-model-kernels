    SET LR0 CR0 ; SET LR2 CR0 ; SET LR6 CR0 ;;
    LD.MULT R0 LR0 {{ cr.masks }} ;;
    SET LR1 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
    SET LR15 CR1 ;;
{% for h in range(2) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.dsfull }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for i in range(8) %}
    MULT.EE LR0 {{ cr.maskval }} 0 LR0 {{ cr.dsfull }}.L {{ cr.qf }}.L ; ACC.RESHAPE LRD0 LRD12 0 ;;
    ADDBI LRD12 1 ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf }}.L {{ cr.masks }} {{ 'LR0' if h == 0 else 'LR15' }} ;;
{% endfor %}
row:
    SET LR10 LR6 ; SET LR11 CR0 ; SET LR5 CR0 ;;
pair:
{% for half in range(2) %}
    LD.MASK {{ 'LR0' if half == 0 else 'LR15' }} {{ cr.masks }} ;;
    SET LR1 LR10 ; SET LR3 LR11 ; SET LR12 CR0 ;;
    SUB LR3 LR3 CR1 ;;
{% if half == 1 %}
    INC LR12 224 ;;
    INC LR12 224 ;;
{% endif %}
{% for chunk in range((k + 127)//128) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    SET LR9 CR0 ; SET LR8 CR0 ;;
    SUB LR9 LR9 CR1 ;;
{% if chunk == 0 and half == 0 %}
    LD.MULT.CYCLIC LR3 {{ cr.in1 }} LR0 ; INC LR3 1 ; INC LR8 1 ; INC LR9 1 ;;
    MULT.RC.VE LR12 LR9 0 LR0 {{ cr.dsfull }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% endif %}
{% if chunk != 0 or half != 0 or k > 1 %}
inner_{{ half }}_{{ chunk }}:
    LD.MULT.CYCLIC LR3 {{ cr.in1 }} LR0 ; INC LR3 1 ; INC LR8 1 ; INC LR9 1 ;;
    MULT.RC.VE LR12 LR9 0 LR0 {{ cr.dsfull }}.L {{ cr.qf }}.L ; ACC.ADD ; BLT.S LR8 {{ cr.tail if chunk == (k+127)//128-1 else cr.full }} inner_{{ half }}_{{ chunk }} ;;
{% endif %}
    INC LR1 1 ;;
{% endfor %}
    ADD LR10 LR10 {{ cr.astride }} ; ADD LR11 LR11 {{ cr.k }} ; INC LR5 1 ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR5 {{ cr.b }} pair ;;
    ADD LR6 LR6 {{ cr.kc }} ;;
    BLT.S LR6 {{ cr.astride }} row ;;
    HALT ;;
