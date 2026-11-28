{% macro loadcoef(reg) %}LD.MULT {{ reg }} LR11 {{ cr.w }} ; INC LR11 1{% endmacro %}
{% if k <= 32 and in0_d2 <= 64 and in0_d3 % 2 == 0 and in0_d3 <= 510 and in0_d0 == 1 %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR1 128 ; INC LR2 224 ; SET LR3 CR0 ;;
    INC LR2 224 ; INC LR3 192 ; SET LR8 CR0 ;;
    INC LR3 192 ; SET LR5 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.zero }} LR3 ; DEC LR5 1 ; SET LR7 CR0 ;;
    INC LR7 {{ in0_d3 // 2 }} ;;
shift_pair:
    SET LR6 CR0 ;;
    INC LR6 {{ k }} ;;
shift_channel:
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR2 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.shifted }} LR5 ; INC LR5 1 ; INC LR8 1 ; DEC LR6 1 ; BNE LR6 CR1 shift_channel ;;
    INC LR8 {{ k }} ; DEC LR7 1 ; BNE LR7 CR1 shift_pair ;;
    SET LR2 CR0 ; SET LR9 CR0 ; SET LR12 CR0 ;;
    INC LR2 64 ; DEC LR12 1 ; SET LR13 CR0 ;;
    DEC LR13 1 ; SET LR14 {{ cr.n }} ; SET LR4 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ; INC LR4 160 ;;
    INC LR4 160 ; INC LR6 128 ; INC LR7 192 ;;
    INC LR6 128 ; INC LR7 192 ;;
packed_channel:
    SET LR8 CR0 ; SET LR15 CR0 ;;
    INC LR15 {{ in0_d3 // 2 }} ;;
packed_pair:
    ADD LR5 LR8 LR8 ; SET LR11 LR9 ; SET LR10 CR0 ;;
    INC LR5 {{ k }} ; DEC LR11 1 ; SET LR3 LR1 ;;
    {{ loadcoef('R0') }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ loadcoef('R0') }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef('R0') }} ;;
    {{ loadcoef('R1') }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.shifted }} LR0 ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR1 ;;
{% for i in range(k) %}
    MULT.RC.VE {{ 'LR2' if i % 2 == 0 else 'LR4' }} LR10 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if not loop.last %}; LD.MULT.CYCLIC LR8 {{ cr.shifted }} {{ 'LR6' if i % 2 == 0 else 'LR0' }} ; INC LR8 1{% endif %}{% if not loop.first %} ; INC LR3 1{% endif %} ;;
    MULT.RC.VE {{ 'LR2' if i % 2 == 0 else 'LR4' }} LR3 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if not loop.last %}; LD.MULT.CYCLIC LR5 {{ cr.in0 }} {{ 'LR7' if i % 2 == 0 else 'LR1' }} ; INC LR5 1 ; INC LR10 1{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR12 ; INC LR12 1 ; INC LR8 1 ; SET LR3 CR0 ;;
    SET LR10 {{ cr.idx_lo }} ; SET LR11 {{ cr.idx_hi }} ;;
{% for i in range(8) %}
    MULT.VE LR0 CR0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD10 0 {% if not loop.first %}; ADDBI LRD10 8{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full_ds }}.H {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR2 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ; INC LR13 2 ; INC LR12 1 ; DEC LR15 1 ; BNE LR15 CR1 packed_pair ;;
    SET LR12 LR13 ; INC LR9 {{ 2 * (1 + chunks) }} ;;
    DEC LR14 1 ; BNE LR14 CR1 packed_channel ;;
    HALT ;;
{% else %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR15 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.zero }} LR0 ; DEC LR5 1 ;;
batch:
    SET LR9 CR0 ; SET LR6 {{ cr.n }} ;;
channel:
    SET LR8 LR15 ; SET LR13 CR0 ;;
{% if in0_d3 <= 255 %}
    INC LR13 {{ in0_d3 }} ;;
{% else %}
    INC LR13 {{ in0_d3 // 256 }} ;;
{% for i in range(8) %}    ADD LR13 LR13 LR13 ;;
{% endfor %}
    INC LR13 {{ in0_d3 % 256 }} ;;
{% endif %}
row:
{% if k <= 32 and tiles == 1 %}
    SET LR11 LR9 ; SET LR4 LR8 ; SET LR10 CR0 ;;
    DEC LR11 1 ; DEC LR4 {{ tiles }} ; SET LR3 CR0 ;;
    {{ loadcoef('R0') }} ; INC LR3 128 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ loadcoef('R0') }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef('R0') }} ;;
    {{ loadcoef('R1') }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; INC LR4 {{ tiles }} ;;
{% for i in range(k) %}
    MULT.RC.VE LR0 LR10 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if not loop.first %}; INC LR3 1{% endif %} ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if not loop.last %}; LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; INC LR4 {{ tiles }} ; INC LR10 1{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; ADD LR8 LR8 {{ cr.row_stride }} ; DEC LR13 1 ; BNE LR13 CR1 row ;;
    ADD LR9 LR11 CR1 ; DEC LR6 1 ; BNE LR6 CR1 channel ;;
    SET LR15 LR8 ; DEC LR2 1 ; BNE LR2 CR1 batch ;;
    HALT ;;
{% else %}
    SET LR12 LR8 ; SET LR7 CR0 ;;
    INC LR7 {{ tiles }} ;;
tile:
    SET LR11 LR9 ; SET LR4 LR12 ; SET LR14 CR0 ;;
    DEC LR11 1 ; DEC LR4 {{ tiles }} ; INC LR14 {{ chunks }} ;;
    {{ loadcoef('R0') }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ loadcoef('R0') }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
chunk:
    SET LR10 CR0 ; SET LR3 CR0 ;;
    INC LR3 128 ;;
    {{ loadcoef('R0') }} ;;
    {{ loadcoef('R1') }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; INC LR4 {{ tiles }} ;;
{% if k <= 32 %}
{% for i in range(k) %}
    MULT.RC.VE LR0 LR10 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if not loop.first %}; INC LR3 1{% endif %} ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if not loop.last %}; LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; INC LR4 {{ tiles }} ; INC LR10 1{% endif %} ;;
{% endfor %}
{% else %}
    SET LR1 CR0 ; DEC LR3 1 ;;
    INC LR1 127 ;;
{% if k % 128 %}
    BNE LR14 CR1 reduce ;;
    SET LR1 CR0 ;;
    INC LR1 {{ (k % 128) - 1 }} ;;
{% endif %}
reduce:
    MULT.RC.VE LR0 LR10 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR10 1 ; BLT.S LR10 LR1 next_scalar ;;
    DEC LR14 1 ; BNE LR14 CR1 chunk ;;
    B finish_reduce ;;
next_scalar:
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; INC LR4 {{ tiles }} ; B reduce ;;
finish_reduce:
{% endif %}
{% endif %}
    BNE LR7 CR1 full_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
    ADD LR8 LR8 {{ cr.row_stride }} ; DEC LR13 1 ; BNE LR13 CR1 row ;;
    ADD LR9 LR11 CR1 ; DEC LR6 1 ; BNE LR6 CR1 channel ;;
    SET LR15 LR8 ; DEC LR2 1 ; BNE LR2 CR1 batch ;;
    HALT ;;
full_tile:
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR12 1 ; DEC LR7 1 ;;
    B tile ;;
{% endif %}
