    SET LR0 CR0 ; SET LR5 CR0 ; SET LR9 CR0 ;;
    SET LR10 {{ cr.n }} ; DEC LR5 1 ;;
feature:
    SET LR8 CR0 ; SET LR11 {{ cr.tiles }} ;;
tile:
    LD.MULT.CYCLIC LR9 {{ cr.w }} LR0 ; SET LR2 LR8 ; SET LR3 CR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR6 {{ cr.tilewidth }} ;;
    BEQ LR11 CR1 last_width ;;
    B pixels ;;
last_width:
    SET LR6 {{ cr.tailwidth }} ;;
pixels:
    SET LR4 LR9 ; SET LR7 {{ cr.kchunks }} ;;
{% if (k + 127) // 128 <= 32 %}
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% for i in range((k + 127) // 128) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; INC LR2 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L {% if not loop.last %}; LD.MULT R0 LR2 {{ cr.in0 }}{% endif %} ;;
{% endfor %}
{% else %}
dot:
    INC LR4 1 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR2 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; DEC LR7 1 ; BNE LR7 CR1 dot ;;
{% endif %}
    INC LR3 1 ; DEC LR6 1 ; BNE LR6 CR1 pixels ;;
    DEC LR11 1 ; BEQ LR11 CR1 last ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; SET LR8 LR2 ; B tile ;;
last:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; ADD LR9 LR9 {{ cr.wstride }} ; DEC LR10 1 ; BNE LR10 CR1 feature ;;
    HALT ;;
