    SET LR0 CR0 ; SET LR5 CR0 ; SET LR10 CR0 ;;
{% for i in range(5) %}
    {% if i %}INC LR10 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR10 ;;
{% endfor %}
    SET LR13 CR0 ; SET LR14 {{ cr.in0_d0 }} ; DEC LR5 1 ;;
    SET LR11 CR0 ;;
    INC LR11 128 ;;
batch:
    SET LR8 LR13 ; SET LR9 CR0 ; SET LR12 {{ cr.rows }} ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ; SET LR1 CR0 ;;
    DEC LR4 1 ; DEC LR1 1 ;;
tile:
    SET LR2 LR8 ; SET LR3 LR9 ; SET LR7 {{ cr.k }} ;;
{% if bias %}
    LD.MULT R0 LR1 {{ cr.b }} ; INC LR1 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% else %}
    MULT.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
chunk:
    SUB LR10 LR11 LR3 ;;
    BLT.S LR7 LR10 short_chunk ;;
count_ready:
    SUB LR7 LR7 LR10 ; ADD LR10 LR10 LR3 ; DEC LR3 1 ;;
    DEC LR10 3 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    BLT.S LR10 LR3 last_tap ;;
tap:
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; BLT.S LR3 LR10 tap ;;
last_tap:
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 ;;
    INC LR3 1 ;;
    BEQ LR3 LR11 advance ;;
    B finish ;;
short_chunk:
    SET LR10 LR7 ; B count_ready ;;
advance:
    SET LR3 CR0 ; INC LR2 1 ;;
    BNE LR7 CR0 chunk ;;
finish:
    DEC LR6 1 ;;
    BNE LR6 CR0 full_tile ;;
    ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
    SET LR8 LR2 ; SET LR9 LR3 ; DEC LR12 1 ;;
    BNE LR12 CR0 row ;;
    ADD LR13 LR13 {{ cr.batch_rows }} ; DEC LR14 1 ;;
    BNE LR14 CR0 batch ;;
    HALT ;;
full_tile:
    ACTIVATE.QUANTIZE generic {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; B tile ;;
