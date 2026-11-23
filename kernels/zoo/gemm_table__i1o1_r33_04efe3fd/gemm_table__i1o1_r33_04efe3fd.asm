{% macro tap() %}
    MULT.RC.VE LR0 LR5 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; INC LR9 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR9 CR0 ; SET LR10 CR0 ;;
    SET LR12 CR0 ; SET LR13 CR0 ; DEC LR9 1 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR10 ;;
    INC LR10 1 ;;
{% endfor %}
batch_loop:
    SET LR1 CR0 ; SET LR7 CR0 ;;
n_loop:
    SET LR2 CR0 ; ADD LR11 LR1 {{ cr.K }} ;;
    DEC LR11 1 ;;
m_loop:
    ADD LR3 LR12 LR2 ; SET LR4 LR1 ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
weight_loop:
    LD.MULT R0 LR4 {{ cr.w }} ; SET LR5 CR0 ; SET LR8 {{ cr.full_bound }} ; BNE LR4 LR11 preload ;;
    SET LR8 {{ cr.tail_bound }} ;;
preload:
    LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ; DEC LR5 1 ; DEC LR8 1 ; BLT.S LR8 CR0 last_tap ;;
# The cyclic load feeds the next multiply; do not prefetch beyond the chunk.
k_loop:
    {{ tap() }} ; LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ; ADD LR3 LR3 {{ cr.MB }} ; INC LR5 1 ; BLT.S LR5 LR8 k_loop ;;
last_tap:
    {{ tap() }} ; INC LR5 1 ; ADD LR3 LR3 {{ cr.MB }} ; INC LR4 1 ; BLT.S LR4 LR11 weight_loop ;;
{% if bias %}
    LD.MULT R0 LR7 {{ cr.b }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% endif %}
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.MB }} full_store ;;
    {{ store(cr.tail_ds) }}
    ADD LR1 LR1 {{ cr.K }} ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.n }} n_loop ;;
    ADD LR12 LR12 LR15 ; INC LR13 1 ;;
    BLT.S LR13 LR14 batch_loop ;;
    HALT ;;
full_store:
    {{ store(cr.full_ds) }}
    BEQ CR0 CR0 m_loop ;;
