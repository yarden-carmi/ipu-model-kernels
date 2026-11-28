{% macro mac() %}MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
    SET LR12 {{ cr.in0_d0 }} ; DEC LR5 1 ;;
batch:
    SET LR10 CR0 ; SET LR13 {{ cr.n }} ;;
feature:
    SET LR14 CR0 ;;
pixel:
    SET LR4 LR10 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% for chunk in range((k + 127) // 128) %}
{% for digit in range(2) %}
    INC LR4 1 ; LD.MULT R0 LR4 {{ cr.w }} ; ADD LR6 LR11 LR14 ; SET LR3 CR0 ;;
    DEC LR3 1 ;;
{% if chunk %}
{% for j in range(chunk) %}
    ADD LR6 LR6 {{ cr.chunkstride }} ;;
{% endfor %}
{% endif %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; SET LR7 CR0 ;;
{% set count = [128, k - chunk * 128] | min %}
{% if count > 1 %}
    SET LR8 CR0 ;;
    INC LR8 {{ count - 2 }} ;;
loop_{{ chunk }}_{{ digit }}:
    {{ mac() }} ; ADD LR6 LR6 {{ cr.pitch }} ; INC LR3 1 ; INC LR7 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; BLT.S LR7 LR8 loop_{{ chunk }}_{{ digit }} ;;
{% endif %}
    {{ mac() }} ; INC LR3 1 ;;
{% endfor %}
{% endfor %}
    BEQ LR14 LR15 lastpixel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR14 1 ; B pixel ;;
lastpixel:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
    ADD LR10 LR10 {{ cr.wr }} ; DEC LR13 1 ; BNE LR13 CR1 feature ;;
    ADD LR11 LR11 {{ cr.batchstride }} ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
