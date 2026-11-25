{% macro gather() %}
    MULT.EE LR6 CR1 0 LR0 {{ cr.tail_and_one }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR2 {{ cr.tail_and_one }}.H
{% endmacro %}
{% macro store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR14 CR0 ;;
    SET LR7 CR0 ; INC LR14 128 ;;
row:
    // RHS row = batch base + column block + height * blocks.
    ADD LR12 LR8 LR9 ; SET LR10 {{ cr.in0_d1 }} ;;
chunk:
    SUB LR2 LR0 CR1 ; SET LR11 CR1 ;;
    SET LR13 LR14 ; BLT.S LR14 LR10 bound ;;
    SET LR13 LR10 ;;
bound:
    SUB LR10 LR10 LR13 ; DEC LR13 1 ; LD.MULT R0 LR12 {{ cr.in1 }} ;;
    BEQ LR13 CR0 last ;;
gather_loop:
    {{ gather() }} ; ADD LR12 LR12 {{ cr.blocks }} ; LD.MULT R0 LR12 {{ cr.in1 }} ; INC LR2 1 ; INC LR11 1 ; BLT.S LR11 LR13 gather_loop ;;
last:
    {{ gather() }} ; INC LR2 1 ; ADD LR12 LR12 {{ cr.blocks }} ; LD.MULT R0 LR5 {{ cr.in0 }} ; BEQ LR10 CR0 tail ;;
    {{ store('CR15.L') }} ;;
    INC LR5 1 ; B chunk ;;
tail:
    {{ store(cr.tail_and_one ~ '.L') }} ;;
    INC LR5 1 ;;
    BEQ LR5 {{ cr.rows }} done ;;
    INC LR6 1 ; INC LR7 1 ;;
    BEQ LR7 LR15 batch ;;
    BLT.S LR6 LR14 row ;;
    SET LR6 CR0 ; INC LR9 1 ; B row ;;
batch:
    ADD LR8 LR8 LR4 ; SET LR9 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; B row ;;
done:
    HALT ;;
