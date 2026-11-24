{% set full = cr.tail ~ '.H' %}
{% if in0_d1 % 128 == 0 and in0_d2 % 128 == 0 %}
{% set q = cr.qf_in0 ~ '.L' %}
{% set tile = cr.tile %}
    SET LR15 LR14 ; SET LR0 CR0 ; SET LR7 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR10 CR0 ;;
    SET LR14 CR0 ; INC LR7 2 ;;
    INC LR14 128 ; SET LR6 CR0 ;;
    // Generate the full-width inverse lift, with the FP32-only correction.
    INC LR6 255 ;;
    INC LR6 1 ; MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ tile }} LR0 ;;
    LD.MULT R0 LR0 {{ tile }} ;;
    MULT.VE LR0 {{ cr.unlift }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    {% for correction in range(5) %}
    MULT.VE LR0 {{ cr.fp_correction }} 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;
    {% if loop.last %}ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ tile }} LR6 ;{% endif %} ;;
    {% endfor %}
block:
    SET LR12 LR8 ; SET LR11 LR15 ;;
chunk:
    // Each radix-2 pass exchanges the low row and lane bits, rotating
    // both indices right. Seven passes transpose a full 128x128 tile.
    {% for stage in range(7) %}
    {% set base = cr.in0 if stage == 0 else tile %}
    {% set scale = cr.lift if stage == 0 else 'CR1' %}
    {% set bank = stage % 2 %}
    SET LR1 {{ 'LR12' if stage == 0 else ('LR0' if bank else 'LR14') }} ; SET LR2 {{ 'LR14' if bank else 'LR0' }} ; SET LR4 CR0 ;;
    ADD LR3 LR2 LR0 ; INC LR4 63 ; SET LR5 CR0 ;;
    INC LR3 63 ;;
    {% macro advance() %}{{ 'ADD LR1 LR1 ' ~ cr.blocks if stage == 0 else 'INC LR1 1' }} ;{% endmacro %}
    LD.MULT R0 LR1 {{ base }} ;;
    {{ advance() }} LD.MULT R1 LR1 {{ base }} ;;
    {% macro even() %}
    MULT.VE LR0 {{ scale }} 0 LR0 {{ full }} {{ q }} ; ACC.STRIDE 16 on off LR0 ; INC LR3 1 ;;
    MULT.VE LR14 {{ scale }} 0 LR0 {{ full }} {{ q }} ; ACC.STRIDE 16 on off LR7 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ tile }} LR2 ;;
    {% endmacro %}
    {% macro odd(last) %}
    MULT.VE LR0 {{ scale }} 0 LR0 {{ full }} {{ q }} ; ACC.STRIDE 16 on_inv off LR0 ; INC LR2 1 ;
    {{ advance() }} {% if not last %}LD.MULT R0 LR1 {{ base }} ;{% endif %} ;;
    MULT.VE LR14 {{ scale }} 0 LR0 {{ full }} {{ q }} ; ACC.STRIDE 16 on_inv off LR7 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ tile }} LR3 ;
    {% if not last %}{{ advance() }} LD.MULT R1 LR1 {{ base }} ; INC LR5 1 ; BLT.S LR5 LR4 pass{{ stage }} ;{% endif %} ;;
    {% endmacro %}
    DEC LR4 1 ;;
pass{{ stage }}:
    {{ even() }}
    {{ odd(false) }}
    {{ even() }}
    {{ odd(true) }}
    {% if stage == 0 %}SET LR12 LR1 ;;{% endif %}
    {% endfor %}
    SET LR1 CR0 ; SET LR13 LR10 ;;
    LD.MULT R0 LR6 {{ tile }} ;;
    LD.MULT.CYCLIC LR1 {{ tile }} LR0 ;;
emit:
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R1 LR13 {{ cr.in1 }} ; INC LR1 1 ;;
    MULT.VE LR14 CR1 0 LR0 {{ full }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    BEQ LR1 LR14 chunk_done ;;
    ADD LR13 LR13 LR15 ; LD.MULT.CYCLIC LR1 {{ tile }} LR0 ;;
    B emit ;;
chunk_done:
    INC LR10 1 ; DEC LR11 1 ; BNE LR11 CR1 chunk ;;
    ADD LR10 LR13 CR1 ; INC LR9 1 ;;
    BEQ LR10 {{ cr.rows }} done ;;
    BEQ LR9 {{ cr.blocks }} batch ;;
    INC LR8 1 ; B block ;;
batch:
    SUB LR8 LR12 LR9 ; INC LR8 1 ; SET LR9 CR0 ; B block ;;
done:
    HALT ;;
{% else %}
{% macro add_store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
{% macro scatter() %}
    MULT.EE LR6 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR14 CR0 ;;
    SET LR7 CR0 ;;
    INC LR14 128 ;;
row:
    ADD LR12 LR8 LR9 ; SET LR10 {{ cr.in0_d2 }} ;;
chunk:
    SET LR13 LR14 ; BLT.S LR14 LR10 gather_setup ;;
    SET LR13 LR10 ;;
gather_setup:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR11 CR0 ;;
    LD.MULT R0 LR12 {{ cr.in0 }} ; DEC LR13 1 ;;
    BEQ LR11 LR13 gather_single ;;
    {{ scatter() }} ; ADD LR12 LR12 {{ cr.blocks }} ; INC LR11 1 ; LD.MULT R0 LR12 {{ cr.in0 }} ;;
    DEC LR13 1 ;;
    BLT.S LR13 LR11 gather_last ;;
gather:
    {{ scatter() }} ; ADD LR12 LR12 {{ cr.blocks }} ; INC LR11 1 ; ADDBI LRD2 1 ; LD.MULT R0 LR12 {{ cr.in0 }} ; BLT.S LR11 LR13 gather ;;
gather_last:
    ADDBI LRD2 1 ;;
gather_single:
    {{ scatter() }} ; LD.MULT R0 LR5 {{ cr.in1 }} ; ADD LR12 LR12 {{ cr.blocks }} ; INC LR11 1 ;;
    BEQ LR10 LR11 tail ;;
    DEC LR10 128 ;;
    {{ add_store(full) }}
    B chunk ;;
tail:
    {{ add_store(cr.tail ~ '.L') }}
    BEQ LR5 {{ cr.rows }} done ;;
    INC LR6 1 ; INC LR7 1 ;;
    BEQ LR7 {{ cr.in0_d1 }} batch ;;
    BLT.S LR6 LR14 row ;;
    SET LR6 CR0 ; INC LR9 1 ;;
    B row ;;
batch:
    SUB LR8 LR12 LR9 ; SET LR9 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ;;
    B row ;;
done:
    HALT ;;
{% endif %}
