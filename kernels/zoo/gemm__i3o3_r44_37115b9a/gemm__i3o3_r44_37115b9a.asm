{# One accumulator lane per spatial position. The two weight digits
   share each input load; the residual MAC prefetches the next channel. #}
{% macro mac(scalar, first=false) %}MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro store(ds) %}INC LR8 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8{% endmacro %}
{% set w = cr.w if bias else cr.w_unbiased %}
{% set wide_tail = out0_d3 > 128 and out0_d3 % 128 != 0 %}
    SET LR0 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    DEC LR8 1 ; SET LR11 {{ cr.batches }} ;;
batch:
    SET LR10 {{ cr.n }} ; SET LR14 CR0 ;;
    DEC LR14 1 ;;
feature:
    SET LR6 LR7 ; SET LR9 {{ cr.out_pitch }} {% if wide_tail %}; SET LR12 LR15{% endif %} ;;
tile:
    SET LR4 LR14 ; SET LR5 LR6 ; SET LR13 {{ cr.panels }} ;;
{% if bias %}
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0 ;;
    {{ mac('CR1', true) }} ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ w }} LR0 ;;
    {{ mac('CR1') }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
{% endif %}
panel:
    INC LR4 1 ; LD.MULT R0 LR4 {{ w }} ; SET LR1 CR0 ; SET LR2 {{ cr.lanes }} ;;
    INC LR4 1 ; LD.MULT R1 LR4 {{ w }} ; SET LR3 {{ cr.lanes }} ;;
    DEC LR1 1 ; DEC LR2 1 ;;
{% if k % 128 %}
{% if k > 128 %}
    BNE LR13 CR1 channel ;;
{% endif %}
    SET LR3 CR0 ;;
    INC LR3 {{ k % 128 }} ;;
{% endif %}
channel:
    {{ mac('LR1') }} ; DEC LR3 1 ; INC LR1 1 ; BEQ LR3 CR1 panel_end ;;
    {{ mac('LR2') }} ; INC LR2 1 ; ADD LR5 LR5 {{ cr.in_pitch }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; B channel ;;
panel_end:
    {{ mac('LR2') }} ; INC LR2 1 ; DEC LR13 1 ; BEQ LR13 CR1 write ;;
    ADD LR5 LR5 {{ cr.in_pitch }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; B panel ;;
write:
{% if wide_tail %}
    DEC LR12 1 ; BEQ LR12 CR1 write_tail ;;
    {{ store(cr.full) }} ; B advance ;;
write_tail:
    {{ store(cr.store_ds) }} ; SET LR12 LR15 ;;
advance:
{% else %}
    {{ store(cr.store_ds) }} ;;
{% endif %}
    INC LR6 1 ; DEC LR9 1 ; BNE LR9 CR1 tile ;;
    SET LR14 LR4 ; DEC LR10 1 ; BNE LR10 CR1 feature ;;
    ADD LR7 LR7 {{ cr.batch_stride }} ; DEC LR11 1 ; BNE LR11 CR1 batch ;;
    HALT ;;
