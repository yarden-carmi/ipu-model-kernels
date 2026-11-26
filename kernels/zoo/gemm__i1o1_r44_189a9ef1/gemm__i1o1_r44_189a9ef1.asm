{% if not bias and k == 96 and n == 144 %}
{% macro wt(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w_unbiased }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro red(slot, dest, first=false) %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{% if first %}.FIRST{% endif %} {{ dest }} {{ cr.full }}.L{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.lanes128 }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR9 {{ cr.points }} ; DEC LR5 1 ;;
special_row:
    SET LR4 CR0 ; SUB LR3 LR0 CR1 ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
    DEC LR4 1 ; SET LR12 CR0 ;;
    INC LR12 96 ; {{ wt('LR0') }} ;;
special_dual:
    {{ red('LR0', 'LR3', true) }} ; INC LR3 1 ; {{ wt('LR1') }} ; DEC LR12 1 ;;
    {{ red('LR1', 'LR3') }} ; {{ wt('LR0') }} ; BNE LR12 CR0 special_dual ;;
    SET LR12 CR0 ;;
    INC LR12 32 ;;
special_single:
    {{ red('LR0', 'LR3', true) }} ; INC LR3 1 ; {{ wt('LR0') }} ; DEC LR12 1 ; BNE LR12 CR1 special_single ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; SUB LR3 LR0 CR1 ; SET LR12 CR0 ;;
    INC LR12 16 ;;
special_tail:
    {{ red('LR0', 'LR3', true) }} ; INC LR3 1 ; {{ wt('LR1') }} ; DEC LR12 1 ; BEQ LR12 CR1 special_last ;;
    {{ red('LR1', 'LR3') }} ; {{ wt('LR0') }} ; B special_tail ;;
special_last:
    {{ red('LR1', 'LR3') }} ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR8 1 ; DEC LR9 1 ; BNE LR9 CR1 special_row ;;
    HALT ;;
{% elif bias and 24 < n and n <= 32 and k <= 64 %}
{# Pack x, a bias lane, and a scaled copy of x in a two-word loop. A
   single dot then includes both coefficient digits and the bias. #}
{% macro dot(slot) %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.full }}.L ; INC LR3 1{% endmacro %}
{% macro next_weight() %}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0{% endmacro %}
{% macro write() %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.lanes128 }} ; SET LR2 CR0 ;;
    INC LR2 63 ; SET LR4 CR1 ; SET LR5 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.w }} LR0 ; SET LR8 {{ cr.points }} ; SET LR9 CR0 ;;
    LD.MULT R1 LR4 {{ cr.w }} ; ADD LR7 LR1 LR1 ;;
    INC LR4 1 ; LD.MULT R0 LR4 {{ cr.w }} ;;
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR1 ; SUB LR5 LR0 CR1 ;;
{% macro original() %}MULT.RC.VV LR1 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST{% endmacro %}
{% macro duplicate() %}MULT.RC.VV LR2 R1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.packed }} LR5 ; INC LR5 1{% endmacro %}
pack:
    {{ original() }} ; BEQ LR8 CR1 pack_last ;;
    {{ duplicate() }} ; INC LR9 1 ; DEC LR8 1 ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR1 ; B pack ;;
pack_last:
    {{ duplicate() }} ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR7 ;;
    LD.MULT R0 LR0 {{ cr.packed }} ; SET LR5 CR0 ; SET LR8 {{ cr.points }} ;;
    SET LR3 CR0 ; DEC LR5 1 ; SET LR6 {{ cr.tail_count }} ;;
    DEC LR6 1 ; SET LR9 CR0 ; SET LR10 LR4 ;;
point:
    MULT.RC.VV LR7 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR0 {{ cr.full }}.L ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR5 1 ;;
{% for i in range(n - 2) %}
    {{ dot('LR0') }} ; {{ next_weight() }} {% if loop.last %}; INC LR9 1 ; BEQ LR8 CR1 finish{% endif %} ;;
{% endfor %}
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR6 {{ cr.full }}.L ; {{ write() }} ; SET LR4 LR10 ; SET LR3 CR0 ; DEC LR8 1 ; LD.MULT R0 LR9 {{ cr.packed }} ; B point ;;
finish:
    {{ dot('LR0') }} ; {{ write() }} ; HALT ;;
{% elif 3 * k + 8 < 2 * ((k + 127) // 128) * n // ((n + 127) // 128) %}
{# Each accumulator lane is an output channel. The cyclic row holds
   the coefficients for one input channel, in coarse/residual pieces. #}
{% macro load() %}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w if bias else cr.w_unbiased }} LR0{% endmacro %}
{% macro mac(src, first=false) %}MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro store(ds) %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR8 {{ cr.points }} ; SET LR9 CR0 ;;
    INC LR9 127 ;;
point:
    SET LR4 CR0 ; SET LR7 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    {{ load() }} ; SET LR5 LR3 ; SET LR6 {{ cr.k }} ;;
    {{ mac('CR1', true) }} ; {{ load() }} ;;
    {{ mac('CR1') }} ;;
chunk:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR1 CR0 ;;
    DEC LR1 1 ;;
channel:
    {{ load() }} ; INC LR1 1 ;;
    {{ mac('LR1') }} ; {{ load() }} ;;
    {{ mac('LR1') }} ; DEC LR6 1 ; BEQ LR6 CR1 finish ;;
    BLT.S LR1 LR9 channel ;;
    {# Increment the input-row offset only on crossing a channel chunk. #}
    INC LR5 1 ; B chunk ;;
finish:
    DEC LR7 1 ; BEQ LR7 CR1 tail ;;
    {{ store(cr.full) }} ;;
    INC LR2 1 ; B tile ;;
tail:
    {{ store(cr.tail) }} ;;
    INC LR2 1 ; ADD LR3 LR3 {{ cr.input_chunks }} ; DEC LR8 1 ; BNE LR8 CR1 point ;;
    HALT ;;
{% else %}
{# Keep the input chunk in R0 and stream two independently quantized
   digits per output lane. Alternate cyclic slots to pipeline the loads. #}
{% macro weight(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w if bias else cr.w_unbiased }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro bias_mac(slot, mode) %}MULT.RC.VE {{ slot }} CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{% macro reduce(slot, dest) %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM {{ dest }} {{ cr.full }}.L{% endmacro %}
{% macro write_tile(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; DEC LR6 1 ; B tile_or_row ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.lanes128 }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR9 {{ cr.points }} ; DEC LR5 1 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ; SET LR7 {{ cr.tail_count }} ;;
    DEC LR4 1 {% if k <= 128 %}; LD.MULT R0 LR8 {{ cr.in0 }}{% endif %} ;;
tile:
{% if n > 128 and n % 128 != 0 %}
    SET LR7 {{ cr.lanes128 }} ; BNE LR6 CR1 init ;;
    SET LR7 {{ cr.tail_count }} ;;
init:
{% endif %}
{% if bias %}
    {{ weight('LR0') }} ;;
    {{ bias_mac('LR0', 'ADD.FIRST') }} ; {{ weight('LR1') }} ;;
    {{ bias_mac('LR1', 'ADD') }} ; SET LR11 {{ cr.input_chunks }} ; SUB LR10 LR8 CR1 ;;
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR11 {{ cr.input_chunks }} ; SUB LR10 LR8 CR1 ;;
{% endif %}
{% if k > 128 %}
chunk:
    LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR10 1 ;;
{% endif %}
    SET LR13 CR0 ;;
    {{ weight('LR0') }} ; SET LR3 CR0 ; SET LR12 LR7 ;;
    DEC LR13 1 ;;
channel:
    {{ reduce('LR0', 'LR3') }} ; {{ weight('LR1') }} ; INC LR13 1 ; DEC LR12 1 ; BEQ LR12 CR1 last_low ;;
    {{ reduce('LR1', 'LR13') }} ; {{ weight('LR0') }} ; INC LR3 1 ; B channel ;;
last_low:
    {{ reduce('LR1', 'LR13') }} {% if k > 128 %}; DEC LR11 1 ; BLT.S CR1 LR11 chunk{% endif %} ;;
{% if n > 128 and n % 128 != 0 %}
    BEQ LR6 CR1 last_tile ;;
    {{ write_tile(cr.full) }}
last_tile:
{% endif %}
    {{ write_tile(cr.tail) }}
tile_or_row:
    BNE LR6 CR0 tile ;;
    ADD LR8 LR8 {{ cr.input_chunks }} ; DEC LR9 1 ;;
    BNE LR9 CR0 row ;;
    HALT ;;
{% endif %}
