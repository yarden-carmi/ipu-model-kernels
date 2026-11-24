{% macro contiguous(pair0, pair1) %}
    SET {{ pair0 }} {{ cr.seq_lo }} ; SET {{ pair1 }} {{ cr.seq_hi }}
{% endmacro %}

{% macro gather64(first) %}
    LD.MULT R0 LR7 {{ cr.tile }} ; INC LR9 64 ;;
{% for block in range(4) %}
    MULT.VE LR6 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ; {% if not first or block != 0 %}ADDBI LRD2 8 ;{% endif %} {% if block != 0 %}DEC LR6 8 ;{% endif %} INC LR7 1 ;;
    MULT.VE LR6 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ; ADDBI LRD2 8 ; INC LR6 8 ; {% if block < 3 %}LD.MULT R0 LR7 {{ cr.tile }} ;{% endif %} ;;
{% endfor %}
    DEC LR6 8 ;;
{% endmacro %}

{% macro add_store(ds) %}
    LD.MULT R0 LR10 {{ cr.operand }} ;;
    MULT.VE LR4 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_operand }}.L ; ACC.ADD ; INC LR10 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ;;
    INC LR11 1 ;;
{% endmacro %}

    SET LR4 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
plane:
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR10 CR0 ;;
    SET LR12 CR0 ; {{ contiguous('LR0', 'LR1') }} ;;
tile_column:
    ADD LR8 LR5 LR10 ; SET LR9 CR0 ;;
tile_row:
    SET LR2 {{ cr.pitch_lo }} ; SET LR3 {{ cr.pitch_hi }} ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
{% for row in range(15) %}
    MULT.VE LR6 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ; {% if row != 0 %}ADDBI LRD2 1 ;{% endif %} LD.MULT R0 LR8 {{ cr.in0 }} ; ADD LR8 LR8 {{ cr.ic }} ;;
{% endfor %}
    MULT.VE LR6 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.tile }} LR7 ; ADDBI LRD2 1 ; ADD LR8 LR8 {{ cr.ic }} ; INC LR9 16 ;;
    INC LR7 1 ;;
    BLT.S LR9 LR14 tile_row ;;
    INC LR12 8 ; INC LR6 8 ;;
    INC.MODP2 LR6 CR0 7 ; BEQ LR12 LR15 emit_plane ;;
    BNE LR6 CR0 tile_column ;;
    INC LR10 1 ; B tile_column ;;

emit_plane:
    SUB LR5 LR8 LR10 ;;
    SET LR6 CR0 ; SET LR8 CR0 ; SET LR10 CR0 ;;
    SET LR12 CR0 ;;
emit_column:
    SET LR7 LR8 ; SET LR9 CR0 ;;
emit_chunk:
    {{ contiguous('LR2', 'LR3') }} ;;
    {{ gather64(true) }}
    BEQ LR9 LR14 half_chunk ;;
    {{ gather64(false) }}
    {{ add_store(cr.full ~ '.L') }}
    BLT.S LR9 LR14 emit_chunk ;;
    B column_done ;;
half_chunk:
    {{ add_store(cr.half ~ '.L') }}
column_done:
    INC LR12 1 ; INC LR6 16 ;;
    INC.MODP2 LR6 CR0 7 ; BEQ LR12 LR15 plane_done ;;
    BNE LR6 CR0 emit_column ;;
    SET LR8 LR7 ; B emit_column ;;
plane_done:
    DEC LR13 1 ;;
    BNE LR13 CR0 plane ;;
    HALT ;;
