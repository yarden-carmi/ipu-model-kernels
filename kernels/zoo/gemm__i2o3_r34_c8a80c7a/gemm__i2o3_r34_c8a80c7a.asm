# The input view maps consecutive pixels to consecutive lanes. Step by
# pitch rows for each input channel, and store one complete pixel block.
{% macro product(scalar) %}MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% endmacro %}
{% macro plane(p) %}
    LD.MULT R0 LR3 {{ cr.w }} ; INC LR3 1 ; SET LR4 CR0 ; SET LR2 LR6 ;;
    MULT.RC.VE LR1 LR4 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if p == 0 %}.FIRST{% endif %} ; SET LR12 {{ cr.k }} ;;
chunk_{{ p }}:
    SET LR13 LR12 ; BLT.S LR12 LR1 load_{{ p }} ;;
    SET LR13 LR1 ;;
load_{{ p }}:
    SUB LR12 LR12 LR13 ; DEC LR13 1 ; INC LR3 1 ;
    LD.MULT R0 LR3 {{ cr.w }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; SET LR4 CR0 ; DEC LR13 1 ; BEQ LR13 CR0 drain_{{ p }} ;;
reduce_{{ p }}:
    {{ product('LR14') }} ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.pitch }} ; SET LR14 LR4 ; INC LR4 1 ; BLT.S LR4 LR13 reduce_{{ p }} ;;
drain_{{ p }}:
    {{ product('LR4') }} ; ADD LR2 LR2 {{ cr.pitch }} ; BLT.S CR0 LR12 chunk_{{ p }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 {{ cr.width }} ; SET LR5 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.w }} LR1 ; SET LR8 CR0 ; SET LR9 {{ cr.out0_d0 }} ; DEC LR5 1 ;;
batch:
    SET LR10 {{ cr.n }} ; SET LR11 CR0 ; ADD LR7 LR8 {{ cr.pitch }} ;;
    DEC LR7 1 ;;
channel:
    SET LR6 LR8 ;;
pixels:
    SET LR3 LR11 ;;
{% for p in range(3) %}
    {{ plane(p) }}
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;
    INC LR5 1 ; INC LR6 1 ; BLT.S LR6 LR7 pixels ;;
    SET LR11 LR3 ; DEC LR10 1 ; BLT.S CR1 LR10 channel ;;
    ADD LR8 LR8 {{ cr.batch_stride }} ; DEC LR9 1 ; BLT.S CR1 LR9 batch ;;
    HALT ;;
