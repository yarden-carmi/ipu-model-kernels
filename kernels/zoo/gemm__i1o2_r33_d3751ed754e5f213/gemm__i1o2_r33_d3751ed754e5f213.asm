{% set packed = 512 <= k <= 1024 and k % 128 == 0 %}
{% macro load(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro mac(slot, scalar, first=false) %}MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro store(ds) %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5{% endmacro %}
{% if k == 128 or packed %}
{# When K fits exactly in one vector, transpose each input block once,
   then keep a complete input row in R0 while streaming output-channel dots. #}
{% set masks = cr.w %}
{% set transposed = cr.batch_arg %}
{% macro masked(index, mask, first=false) %}MULT.RC.VV {{ index }} {{ mask }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{# Butterfly stage: exchange one row-index bit with the corresponding
   lane-index bit, using complementary masks and shifted cyclic reads. #}
{% macro transpose(s, bit) %}
    SET LR2 {{ 'LR11' if s == 0 else 'CR0' }} ; SET LR4 {{ 'LR13' if packed and s == 6 else 'CR0' }} ;;
    {% if s > 0 and s % 2 == 0 %}INC LR2 128 ;;{% endif %}
    {% if s % 2 == 1 %}INC LR4 128 ;;{% endif %}
    ADD LR12 LR4 LR1 ; SET LR14 CR0 ; SET LR15 LR1 ;;
    INC LR14 {{ bit }} ; DEC LR15 {{ bit }} ;;
    LD.MULT R0 LR7 {{ masks }} ;;
    INC LR7 1 ; LD.MULT R1 LR7 {{ masks }} ;;
    INC LR7 1 ;;
group_{{s}}:
    SET LR3 LR2 ; SET LR6 LR4 ; SET LR10 LR4 ;;
    {% if s == 0 %}ADD LR3 LR3 {{ cr.pitch }}{% else %}INC LR3 {{ bit }}{% endif %} ; INC LR6 {{ bit }} ; INC LR10 {{ bit }} ;;
pair_{{s}}:
    LD.MULT.CYCLIC LR2 {{ cr.in0 if s == 0 else transposed }} LR0 ;;
    LD.MULT.CYCLIC LR3 {{ cr.in0 if s == 0 else transposed }} LR1 ;;
    {{ masked('LR0', 'R0', true) }} ;;
    {{ masked('LR15', 'R1') }} ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ transposed }} LR4 ;;
    {{ masked('LR14', 'R0', true) }} ; {% if s == 0 %}ADD LR2 LR2 {{ cr.pitch }}{% else %}INC LR2 1{% endif %} ; INC LR4 1 ;;
    {{ masked('LR1', 'R1') }} ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ transposed }} LR6 ; {% if s == 0 %}ADD LR3 LR3 {{ cr.pitch }}{% else %}INC LR3 1{% endif %} ; BEQ LR4 LR10 group_end_{{s}} ;;
    INC LR6 1 ; B pair_{{s}} ;;
group_end_{{s}}:
    SET LR2 LR3 ; SET LR4 LR6 ; INC LR6 1 ;;
    INC LR4 1 ; BNE LR6 LR12 group_{{s}} ;;
    {% if s == 0 %}SET {{ 'LR11' if packed else 'LR13' }} LR2 ;;{% endif %}
{% endmacro %}
{% macro dot() %}MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L{% endmacro %}
{% macro weight() %}LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ;;
    SET LR8 {{ cr.in0_d0 }} ; SET LR11 CR0 ; SET LR13 CR0 ;;
dot_batch:
    SET LR9 {{ cr.in0_d1 }} ;;
transpose_chunk:
{% if packed %}
    ADD LR13 LR1 LR1 ;;
transpose_slab:
{% endif %}
    SET LR7 CR0 ;;
{% for s in range(7) %}
    {{ transpose(s, 2 ** s) }}
{% endfor %}
{% if packed %}
    SET LR2 {{ cr.k }} ; INC LR13 128 ;;
    INC LR2 128 ;;
    INC LR2 128 ;;
    BNE LR13 LR2 transpose_slab ;;
    ADD LR2 LR1 LR1 ; SET LR14 CR0 ;;
    INC LR14 126 ; ADD LR15 LR2 LR1 ;;
packed_row:
    SET LR7 {{ cr.tiles }} ; SET LR4 CR0 ;;
    INC LR4 13 ;;
packed_tile:
    {{ load('LR0') }} ; SET LR6 LR2 ; SET LR12 {{ cr.k }} ;;
    {{ mac('LR0', 'CR1' if bias else 'CR0', true) }} ; {{ load('LR1') }} ; SET LR3 CR0 ;;
    {{ mac('LR1', 'CR1' if bias else 'CR0') }} ; LD.MULT R0 LR6 {{ transposed }} ; DEC LR3 1 ;;
    {{ load('LR0') }} ;;
packed_channel:
    {{ mac('LR0', 'LR3') }} ; {{ load('LR1') }} ; INC LR3 1 ; BEQ LR3 LR14 packed_last_channel ;;
    {{ mac('LR1', 'LR3') }} ; {{ load('LR0') }} ; B packed_channel ;;
packed_last_channel:
    {{ mac('LR1', 'LR3') }} ; {{ load('LR0') }} ; DEC LR12 128 ; BEQ LR12 LR1 packed_store ;;
    LD.MULT R0 LR6 {{ transposed }} ; INC LR6 128 ; DEC LR3 128 ; B packed_channel ;;
packed_store:
    DEC LR4 1 ; DEC LR7 1 ; BEQ LR7 CR1 packed_tail ;;
    {{ store(cr.full) }} ;; INC LR5 1 ; B packed_tile ;;
packed_tail:
    {{ store(cr.tail) }} ; DEC LR9 1 ;;
    INC LR5 1 ; INC LR2 1 ; BEQ LR9 CR0 packed_next_batch ;;
    BNE LR2 LR15 packed_row ;;
    SUB LR11 LR11 {{ cr.span }} ;;
    INC LR11 1 ; B transpose_chunk ;;
packed_next_batch:
    DEC LR8 1 ; SUB LR11 LR11 {{ cr.pitch }} ;;
    INC LR11 1 ; BNE LR8 CR0 dot_batch ;;
    HALT ;;
{% else %}
    SET LR2 CR0 ;;
dot_row:
    LD.MULT R0 LR2 {{ transposed }} ; SET LR7 {{ cr.tiles }} ; SET LR4 CR0 ;;
    INC LR4 13 ;;
dot_tile:
    {{ weight() }} ; SET LR3 CR0 ;;
    {{ weight() }} ; {{ mac('LR0', 'CR1' if bias else 'CR0', true) }} ; SET LR10 LR1 ; DEC LR3 1 ;;
    DEC LR10 1 ;;
dot_loop:
    {{ dot() }} ; {{ weight() }} ; INC LR3 1 ; DEC LR10 1 ; BNE LR10 CR1 dot_loop ;;
dot_last:
    {{ dot() }} ; INC LR3 1 ; DEC LR7 1 ; BEQ LR7 CR1 dot_tail ;;
    {{ store(cr.full) }} ;; INC LR5 1 ; B dot_tile ;;
dot_tail:
    {{ store(cr.tail) }} ; DEC LR9 1 ;;
    INC LR5 1 ; INC LR2 1 ; BEQ LR9 CR0 dot_next_batch ;;
    BNE LR2 LR1 dot_row ;;
    INC LR11 1 ; B transpose_chunk ;;
dot_next_batch:
    DEC LR8 1 ; SUB LR11 LR13 {{ cr.pitch }} ;;
    INC LR11 1 ; BNE LR8 CR0 dot_batch ;;
    HALT ;;
{% endif %}
{% else %}
{% macro mac_pair(scalar, first=false, next_input=false) %}
    {{ mac('LR0', scalar, first) }} ; {{ load('LR1') }}{% if first %} ; DEC LR12 1{% endif %} ;;
    {{ mac('LR1', scalar) }}{% if next_input %} ; LD.MULT R0 LR2 {{ cr.in0 }}{% endif %}
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 {{ cr.span }} ; SET LR5 CR0 ;;
    SET LR8 {{ cr.in0_d0 }} ; SET LR11 CR0 ; SET LR14 CR0 ;;
batch:
    SET LR9 {{ cr.in0_d1 }} ; SET LR10 CR0 ;;
row:
    SET LR4 CR0 ; SET LR13 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR11 ; SET LR12 {{ cr.k }} ; {{ load('LR0') }} ;;
    {{ mac_pair('CR1' if bias else 'CR0', true, true) }} ; BEQ LR12 CR0 reduce_last ;;
    # MULT sees the previous R0 while the load slot fetches the next K row.
reduce:
    {{ load('LR0') }} ; DEC LR12 1 ; ADD LR2 LR2 {{ cr.pitch }} ;;
    {{ mac_pair('LR10', next_input=true) }} ; BNE LR12 CR0 reduce ;;
reduce_last:
    {{ load('LR0') }} ;;
    {{ mac_pair('LR10') }} ;;
    DEC LR13 1 ;;
    BEQ LR13 CR0 tail ;;
    {{ store(cr.full) }} ;; INC LR5 1 ; B tile ;;
tail:
    {{ store(cr.tail) }} ;; INC LR5 1 ; DEC LR9 1 ; INC LR10 1 ;;
    BEQ LR9 CR0 next_batch ;;
    BNE LR10 LR1 row ;;
    SET LR10 CR0 ; INC LR11 1 ; B row ;;
next_batch:
    DEC LR8 1 ;;
    BEQ LR8 CR0 done ;;
    ADD LR14 LR14 {{ cr.batch_arg }} ;;
    SET LR11 LR14 ; B batch ;;
done:
    HALT ;;
{% endif %}
