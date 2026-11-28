{% set w = cr.w if bias else cr.w_unbiased %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
    DEC LR5 1 ; SET LR12 {{ cr.rows }} ;;
row:
    SET LR10 CR0 ; SET LR13 {{ cr.n }} ;;
feature:
    SET LR4 LR10 ; LD.MULT.CYCLIC LR4 {{ w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR14 CR0 ; SET LR8 {{ cr.chunks }} ;;
chunk:
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0 ;;
{% for digit in range(2) %}
{% if out0_d3 <= 32 %}
    ADD LR6 LR11 LR14 ; SET LR3 CR0 ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR3 1 ;;
{% for pixel in range(out0_d3) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR3 1 {% if not loop.last %}; ADD LR6 LR6 {{ cr.chunks }} ; LD.MULT R0 LR6 {{ cr.in0 }}{% elif digit == 0 %}; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0{% endif %} ;;
{% endfor %}
{% else %}
    ADD LR6 LR11 LR14 ; SET LR3 CR0 ; SET LR9 {{ cr.width }} ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR3 1 ; DEC LR9 1 ;;
    BEQ LR9 CR0 last_{{ digit }} ;;
pixel_{{ digit }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR3 1 ; ADD LR6 LR6 {{ cr.chunks }} ; DEC LR9 1 ; LD.MULT R0 LR6 {{ cr.in0 }} ; BNE LR9 CR1 pixel_{{ digit }} ;;
last_{{ digit }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR3 1 {% if digit == 0 %}; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0{% endif %} ;;
{% endif %}
{% endfor %}
    INC LR14 1 ; DEC LR8 1 ; BNE LR8 CR1 chunk ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
    INC LR10 {{ 2 + 2 * ((k + 127) // 128) }} ; DEC LR13 1 ; BNE LR13 CR1 feature ;;
    ADD LR11 LR11 {{ cr.row_stride }} ; DEC LR12 1 ; BNE LR12 CR1 row ;;
    HALT ;;
