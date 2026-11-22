{% macro load(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro planes(scalar, epilogue='', first=false) %}
{% for p in range(3) %}
    MULT.RC.VE {{ 'LR1' if p == 1 else 'LR0' }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first and p == 0 %}.FIRST{% endif %}{% if p < 2 %} ; {{ load('LR0' if p == 1 else 'LR1') }}{% else %}{{ epilogue }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 {{ cr.width }} ; SET LR5 CR0 ;;
    SET LR8 {{ cr.out0_d0 }} ; SET LR11 CR0 ; SET LR14 CR0 ;;
batch:
    SET LR9 {{ cr.m }} ; SET LR10 CR0 ;;
row:
    SET LR4 CR0 ; SET LR13 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR11 ; SET LR12 {{ cr.k }} ; {{ load('LR0') }} ;;
    {{ planes('CR1' if bias else 'CR0', first=true) }}
reduce:
    LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR12 1 ;;
    {{ load('LR0') }} ; ADD LR2 LR2 {{ cr.pitch }} ;;
    {{ planes('LR10', ' ; BNE LR12 CR0 reduce') }}
    DEC LR13 1 ;;
    BEQ LR13 CR0 tail ;;
    {{ store(cr.full) }}
    B tile ;;
tail:
    {{ store(cr.tail) }}
    DEC LR9 1 ; INC LR10 1 ;;
    BEQ LR9 CR0 next_batch ;;
    BNE LR10 LR1 row ;;
    SET LR10 CR0 ; INC LR11 1 ; B row ;;
next_batch:
    DEC LR8 1 ;;
    BEQ LR8 CR0 done ;;
    ADD LR14 LR14 {{ cr.batch_stride }} ;;
    SET LR11 LR14 ; B batch ;;
done:
    HALT ;;
