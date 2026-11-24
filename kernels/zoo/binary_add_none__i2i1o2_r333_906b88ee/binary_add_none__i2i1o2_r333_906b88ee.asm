{% set blocks = cr.blocks %}
{% set iq = cr.qf_in1 ~ '.L' %}
{% macro store(ds, ptr) %}
    MULT.VE LR6 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} {{ ptr }}
{% endmacro %}
{% macro gather() %}
    MULT.EE LR6 CR1 0 LR0 {{ cr.tail_and_one }}.H {{ iq }} ; AGG.SUM.FIRST LR2 {{ cr.tail_and_one }}.H
{% endmacro %}

{% macro stride(src, parity, dest, first) %}
    MULT.RC.VE {{ src }} {{ 'LR0' if first else 'CR1' }} 0 LR0 CR15.L {{ iq }} ;
    ACC.STRIDE 64 {{ parity }} off {{ dest }}
{% endmacro %}

{# Exchange the low row and lane bits and rotate both indices right.
   Seven exchanges transpose a 128x128 tile. Each input pair feeds both outputs. #}
{% macro exchange(stage) %}
{% set step = 'ADD LR2 LR2 ' ~ blocks if stage == 0 else 'INC LR2 1' %}
{% set base = cr.in1 if stage == 0 else cr.tiles %}
{% if stage == 0 %}
    SUB LR2 LR3 {{ blocks }} ; SET LR5 CR0 ; SET LR9 CR0 ;;
{% elif stage % 2 %}
    SUB LR2 LR0 CR1 ; SET LR5 LR6 ; SET LR9 LR6 ;;
{% else %}
    SUB LR2 LR6 CR1 ; SET LR5 CR0 ; SET LR9 CR0 ;;
{% endif %}
    SET LR10 LR5 ; DEC LR5 1 ; INC LR9 63 ;;
    INC LR10 63 ;;
exchange_{{ stage }}:
    {{ step }} ; INC LR5 1 ; INC LR10 1 ; LD.MULT.CYCLIC LR2 {{ base }} LR0 ;;
    {{ step }} ; {{ stride('LR0', 'on', 'LR0', stage == 0) }} ; LD.MULT.CYCLIC LR2 {{ base }} LR6 ;;
    {{ stride('LR6', 'on', 'LR1', stage == 0) }} ; ACTIVATE.QUANTIZE identity CR15.L {{ iq }} {{ cr.tiles }} LR5 ;;
    {{ stride('LR0', 'on_inv', 'LR0', stage == 0) }} ;;
    {{ stride('LR6', 'on_inv', 'LR1', stage == 0) }} ; ACTIVATE.QUANTIZE identity CR15.L {{ iq }} {{ cr.tiles }} LR10 ; BLT.S LR5 LR9 exchange_{{ stage }} ;;
{% if stage == 0 %}
    ADD LR3 LR2 {{ blocks }} ;;
{% endif %}
{% endmacro %}

    SET LR12 LR15 ; SET LR13 {{ cr.in0_d2 }} ;;
    INC.MODP2 LR12 CR0 7 ; INC.MODP2 LR13 CR0 7 ;;
    BNE LR12 CR0 scalar ;;
    BEQ LR13 CR0 tiled ;;
scalar:
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR14 CR0 ;;
    SET LR7 CR0 ; INC LR14 128 ;;
row:
    ADD LR12 LR8 LR9 ; SET LR10 {{ cr.in0_d2 }} ;;
chunk:
    SUB LR2 LR0 CR1 ; SET LR11 CR1 ;;
    SET LR13 LR14 ; BLT.S LR14 LR10 bound ;;
    SET LR13 LR10 ;;
bound:
    SUB LR10 LR10 LR13 ; DEC LR13 1 ; LD.MULT R0 LR12 {{ cr.in1 }} ;;
    BEQ LR13 CR0 last ;;
gather_loop:
    {{ gather() }} ; ADD LR12 LR12 {{ blocks }} ; LD.MULT R0 LR12 {{ cr.in1 }} ; INC LR2 1 ; INC LR11 1 ; BLT.S LR11 LR13 gather_loop ;;
last:
    {{ gather() }} ; INC LR2 1 ; ADD LR12 LR12 {{ blocks }} ; LD.MULT R0 LR5 {{ cr.in0 }} ; BEQ LR10 CR0 tail ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; B chunk ;;
tail:
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail_and_one }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail_and_one }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
    BEQ LR5 {{ cr.rows }} done ;;
    INC LR6 1 ; INC LR7 1 ;;
    BEQ LR7 LR15 batch ;;
    BLT.S LR6 LR14 row ;;
    SET LR6 CR0 ; INC LR9 1 ; B row ;;
batch:
    ADD LR8 LR8 LR4 ; SET LR9 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; B row ;;

tiled:
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR6 CR0 ;;
    INC LR1 2 ; INC LR6 128 ; SET LR11 LR4 ;;
    SET LR3 CR0 ; SET LR7 CR0 ; SET LR12 LR15 ;;
    // Generate exact power-of-two scratch scales once (also in FP32 mode).
    ADD LR8 LR6 LR6 ; LD.MULT R0 LR0 {{ cr.in1 }} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ iq }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 CR15.L {{ iq }} {{ cr.tiles }} LR8 ;;
    LD.MULT R0 LR8 {{ cr.tiles }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ iq }} ; ACC.SUB.FIRST ;;
{% for i in range(7) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ iq }} ; ACC.SUB {% if loop.last %}; ACTIVATE.QUANTIZE exp2 CR15.L {{ iq }} {{ cr.tiles }} LR8 {% endif %};;
{% endfor %}
    LD.MULT R0 LR8 {{ cr.tiles }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ iq }} ; ACC.ADD.FIRST ; INC LR8 1 ; ACTIVATE.QUANTIZE reciprocal CR15.L {{ iq }} {{ cr.tiles }} LR8 ;;
block:
    SET LR13 {{ cr.in0_d2 }} ;;
tile:
    LD.MULT R0 LR8 {{ cr.tiles }} ;;
{% for stage in range(7) %}
    {{ exchange(stage) }}
{% endfor %}
    DEC LR8 1 ; LD.MULT R0 LR8 {{ cr.tiles }} ;;
    SUB LR4 LR7 LR14 ; SET LR5 CR0 ; SET LR9 LR6 ; LD.MULT.CYCLIC LR0 {{ cr.tiles }} LR0 ;;
    DEC LR9 1 ; INC LR8 1 ;;
add_row:
    ADD LR4 LR4 LR14 ; MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ iq }} ; ACC.ADD.FIRST ; LD.MULT R1 LR4 {{ cr.in0 }} ;;
    INC LR5 1 ; {{ store('CR15.L', 'LR4') }} ; LD.MULT.CYCLIC LR5 {{ cr.tiles }} LR0 ; BLT.S LR5 LR9 add_row ;;
    INC LR7 1 ; DEC LR13 128 ;;
    BNE LR13 CR0 tile ;;
    DEC LR12 128 ;;
    BEQ LR12 CR0 next_batch ;;
    SUB LR3 LR3 LR11 ;;
    INC LR3 1 ;;
    B next_block ;;
next_batch:
    SUB LR3 LR3 {{ blocks }} ; SET LR12 LR15 ;;
    INC LR3 1 ;;
next_block:
    ADD LR7 LR4 CR1 ;;
    BNE LR7 {{ cr.rows }} block ;;
done:
    HALT ;;
