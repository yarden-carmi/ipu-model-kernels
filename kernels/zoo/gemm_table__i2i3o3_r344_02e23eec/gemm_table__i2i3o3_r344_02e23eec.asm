{% set tiles = (m + 127) // 128 %}
{% set last = (m - 1) % 128 + 1 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro store(fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
{% macro repack_store(ds) %}
    ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_in0 }}.L {{ cr.spatial }} LR7 ;;
    LD.MULT.CYCLIC LR7 {{ cr.spatial }} LR14 ;;
    MULT.RC.VE LR14 CR1 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; INC LR7 1 ;;
    ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_in0 }}.L {{ cr.spatial }} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}

    # Walk the view's flat stream, skipping padding in each stored row group.
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; SET LR11 LR14 ; SET LR12 CR0 ;;
    SET LR14 CR0 ; SET LR15 CR0 ;;
    INC LR12 128 ; INC LR15 {{ last }} ;;
input_channel:
    SET LR10 CR0 ;;
    INC LR10 {{ tiles }} ;;
input_tile:
    SET LR8 LR12 ; DEC LR10 1 ;;
    BNE LR10 CR0 pack_tile ;;
    SET LR8 LR15 ;;
pack_tile:
    SET LR9 CR0 ; SET LR0 LR2 ; SET LR1 LR3 ;;
pack_octet:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR5 CR1 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD0 0 ; INC LR6 8 ; INC LR9 8 ;;
    INC LR5 8 ;;
    ADDBI LRD0 8 ; BEQ LR6 LR13 next_stored_item ;;
    BNE LR5 LR12 packed_octet ;;
    INC LR4 1 ; SET LR5 CR0 ; BEQ LR14 CR0 packed_octet ;;
next_stored_item:
    INC LR4 1 ; SET LR5 CR0 ; SET LR6 CR0 ;;
packed_octet:
    BLT.S LR9 LR8 pack_octet ;;
    BNE LR10 CR0 pack_full ;;
    {{ repack_store(cr.tail) }}
    DEC LR11 1 ;;
    BNE LR11 CR0 input_channel ;;
    BEQ LR14 CR0 copy_init ;;
pack_full:
    {{ repack_store(cr.full) }}
    BEQ LR14 CR0 input_tile ;;

copy_init:
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
    INC LR2 1 ;;
{% endfor %}
copy_channel:
    SET LR3 CR0 ;;
    INC LR3 {{ tiles }} ;;
copy_tile:
    LD.MULT.CYCLIC LR1 {{ cr.in1 }} LR0 ; DEC LR3 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    BNE LR3 CR0 copy_full ;;
    {{ store('identity', cr.tail) }}
    BLT.S LR1 {{ cr.copy_rows }} copy_channel ;;
    BEQ LR0 CR0 gemm_init ;;
copy_full:
    {{ store('identity', cr.full) }}
    BEQ LR0 CR0 copy_tile ;;

{% macro mac(preload) %}
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    MULT.RC.VE LR15 LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    # Each split activation row can be replaced as soon as its last multiply reads it.
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR8 1 {% if preload %}; LD.MULT.CYCLIC LR7 {{ cr.spatial }} LR0 ; ADD LR11 LR7 CR1{% endif %} ;;
    MULT.RC.VE LR15 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1 {% if preload %}; LD.MULT.CYCLIC LR11 {{ cr.spatial }} LR15 ; ADD LR7 LR7 LR12{% endif %} ;;
{% endmacro %}
{% macro chunk(count, label) %}
    SET LR10 CR0 ;;
    LD.MULT R0 LR5 {{ cr.w }} ; SET LR8 CR0 ; SET LR9 LR15 ;;
    INC LR5 1 ; INC LR10 {{ count // 8 }} ;;
    LD.MULT R1 LR5 {{ cr.w }} ;;
    INC LR5 1 ;;
{{ label }}:
    LD.MULT.CYCLIC LR7 {{ cr.spatial }} LR0 ; ADD LR11 LR7 CR1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.spatial }} LR15 ; ADD LR7 LR7 LR12 ;;
{% for i in range(8) %}
    {{ mac(not loop.last) }}
{% endfor %}
    DEC LR10 1 ;;
    BNE LR10 CR0 {{ label }} ;;
{% endmacro %}
gemm_init:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR6 CR0 ;;
    SET LR12 CR0 ; SET LR15 CR0 ;;
    INC LR12 {{ 2 * tiles }} ; INC LR15 128 ;;
channel:
    SET LR4 LR12 ; SET LR13 CR0 ;;
tile:
    SET LR5 LR3 ; SET LR7 LR13 ; DEC LR4 2 ;;
{% if bias %}
    LD.MULT R0 LR6 {{ cr.b }} ; ADD LR11 LR6 CR1 ;;
    LD.MULT R1 LR11 {{ cr.b }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR15 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
{% if k > 128 %}
    SET LR14 CR0 ;;
    INC LR14 {{ (k - 1) // 128 }} ;;
full_chunk:
    {{ chunk(128, 'full_group') }}
    DEC LR14 1 ;;
    BNE LR14 CR0 full_chunk ;;
{% endif %}
    {{ chunk((k - 1) % 128 + 1, 'tail_group') }}
    BNE LR4 CR0 gemm_full ;;
    {{ store(act, cr.tail) }}
    SET LR3 LR5 ; INC LR6 2 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.n }} channel ;;
    HALT ;;
gemm_full:
    {{ store(act, cr.full) }}
    INC LR13 2 ; BEQ LR0 CR0 tile ;;
