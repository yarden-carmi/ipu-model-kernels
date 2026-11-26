{# R_CYCLIC holds zero in slot 0 and the current input row in slot 1.
   Starting the vector at 128-j translates a short input row by j lanes. #}
{% macro panel(count, label) %}
    INC LR4 1 ; LD.MULT R0 LR4 {{ cr.coeff }} ; SET LR5 CR0 ; SET LR6 LR1 ;;
    INC LR4 1 ; LD.MULT R1 LR4 {{ cr.coeff }} ; SET LR10 CR0 ;;
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR1 ; INC LR10 {{ count }} ; DEC LR5 1 ; DEC LR6 1 ;;
{{ label }}:
    MULT.RC.VE LR2 LR5 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR5 1 ; DEC LR10 1 ; BEQ LR10 CR1 {{ label }}_last ;;
    MULT.RC.VE LR2 LR6 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR6 1 ; LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR1 ; ADD LR7 LR7 {{ cr.pitch }} ; B {{ label }} ;;
{{ label }}_last:
    MULT.RC.VE LR2 LR6 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR6 1 ; ADD LR7 LR7 {{ cr.pitch }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR14 CR0 ;;
    INC LR1 128 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ; SET LR15 {{ cr.out0_d0 }} ; SUB LR11 LR0 CR1 ;;
    SET LR10 LR1 ; SET LR4 CR1 ;;
    INC LR10 128 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR10 ;;
batch:
    SET LR3 CR1 ; SET LR13 {{ cr.out0_d2 }} ;;
    INC LR3 1 ;;
channel:
    SET LR8 LR14 ; SET LR12 {{ cr.tiles }} ;;
tile:
    LD.MULT R0 LR3 {{ cr.coeff }} ; SET LR2 LR1 ; SET LR9 LR8 ;;
    ADD LR10 LR1 LR1 ; MULT.RC.VE LR10 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
segment:
    SET LR4 LR3 ; SET LR7 LR9 ;;
{% for start in range(0, k, 128) %}
    {{ panel([128, k-start] | min, 'taps_' ~ loop.index) }}
{% endfor %}
    INC LR9 1 ; SUB LR2 LR2 {{ cr.segment }} ;;
    BNE LR2 CR0 segment ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ; INC LR11 1 ; SET LR8 LR9 ; DEC LR12 1 ; BNE LR12 CR1 tile ;;
    ADD LR3 LR3 {{ cr.coeff_stride }} ; DEC LR13 1 ; BNE LR13 CR1 channel ;;
    ADD LR14 LR14 {{ cr.batch_rows }} ; DEC LR15 1 ; BNE LR15 CR1 batch ;;
    HALT ;;
