{% set KC = (k + 127) // 128 %}
{% set NC = (n + 127) // 128 %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR5 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ;;
batch_loop:
    SET LR6 CR0 ;;
m_loop:
{% for t in range(NC) %}
    SET LR1 LR11 ; SET LR3 LR10 ;;
    SUB LR1 LR1 CR1 ; SUB LR3 LR3 CR1 ;;
{% for offset in range(t) %}
    ADD LR3 LR3 {{ cr.w0 }} ;;
{% endfor %}
{% set width = cr.w1 if t == NC - 1 else cr.w0 %}
{% for i in range(KC) %}
{% set kd = cr.klast if i == KC - 1 else cr.kfull %}
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR1 1 ;;
    SET LR7 CR0 ; SET LR8 {{ width }} ;;
    SUB LR7 LR7 CR1 ;;
inner_{{ t }}_{{ i }}:
    LD.MULT.CYCLIC LR3 {{ cr.in1 }} LR0 ; INC LR3 1 ; INC LR7 1 ; DEC LR8 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ kd }}.L {{ cr.qf }}.L ; AGG.SUM{{ '.FIRST' if i == 0 else '' }} LR7 {{ kd }}.L ; BNE LR8 CR0 inner_{{ t }}_{{ i }} ;;
{% if i < KC - 1 %}
    ADD LR3 LR3 {{ cr.n }} ;;
    SUB LR3 LR3 {{ width }} ;;
{% endif %}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.od1 if t == NC - 1 else cr.od0 }}.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
{% endfor %}
    ADD LR11 LR11 {{ cr.kchunks }} ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.m }} m_loop ;;
{% for i in range(KC) %}
    ADD LR10 LR10 {{ cr.n }} ;;
{% endfor %}
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.b }} batch_loop ;;
    HALT ;;
