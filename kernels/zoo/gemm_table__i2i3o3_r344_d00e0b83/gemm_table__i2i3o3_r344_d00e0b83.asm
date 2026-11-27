{% set tiles = (m + 127) // 128 %}
{% set last = (m - 1) % 128 + 1 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro store(fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
{% macro repack_store(ds) %}
    ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_in0 }}.L {{ cr.spatial }} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}

    # Walk the view's flat stream in 16-element blocks. Each pair of
    # scatters shares a load and never crosses a stored row boundary.
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
pack_pair:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR5 CR1 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD0 0 ; INC LR6 16 ; INC LR9 16 ;;
    MULT.VE LR5 CR1 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD0 0 ; INC LR5 8 ; ADDBI LRD0 8 ;;
    INC LR5 8 ; ADDBI LRD0 8 ; BEQ LR6 LR13 next_stored_item ;;
    BNE LR5 LR12 packed_octet ;;
    INC LR4 1 ; SET LR5 CR0 ; BEQ LR14 CR0 packed_octet ;;
next_stored_item:
    INC LR4 1 ; SET LR5 CR0 ; SET LR6 CR0 ;;
packed_octet:
    BLT.S LR9 LR8 pack_pair ;;
    BNE LR10 CR0 pack_full ;;
    {{ repack_store(cr.tail) }}
    DEC LR11 1 ;;
    BNE LR11 CR0 input_channel ;;
    BEQ LR14 CR0 copy_init ;;
pack_full:
    {{ repack_store(cr.full) }}
    BEQ LR14 CR0 input_tile ;;

copy_init:
    # Concatenation prefix: gather padded scanlines into packed output rows.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR8 ;;
    INC LR8 1 ;;
{% endfor %}
    SET LR7 CR0 ;;
    INC LR7 {{ in1_d2 }} ;;
copy_channel:
    SET LR6 LR7 ;;
copy_tile:
    SET LR4 LR2 ; SET LR5 LR3 ; SET LR8 CR0 ;;
skip_row:
    LD.MULT R0 LR0 {{ cr.in1 }} ; DEC LR6 1 ; SET LR8 CR0 ;;
{% for octet in range(in1_d3 // 8) %}
    MULT.VE LR8 CR1 0 LR9 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD2 LRD4 0 {% if not loop.first %}; ADDBI LRD4 8 ; INC LR8 8{% endif %}{% if loop.last %} ; INC LR0 1{% endif %} ;;
{% endfor %}
    ADDBI LRD4 8 ; BEQ LR6 CR0 skip_tail ;;
    BLT.S LR5 LR3 copy_full ;;
    BEQ LR9 CR0 skip_row ;;
skip_tail:
    {{ store('identity', cr.tail) }}
    BLT.S LR0 {{ cr.skip_rows }} copy_channel ;;
    BEQ LR9 CR0 gemm_init ;;
copy_full:
    {{ store('identity', cr.full) }}
    BEQ LR9 CR0 copy_tile ;;

{% macro mac(preload) %}
    # Keep both weight components, but share one spatial row between them.
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1 ;;
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR8 1 {% if preload %}; LD.MULT.CYCLIC LR7 {{ cr.spatial }} LR0 ; INC LR7 {{ tiles }}{% endif %} ;;
{% endmacro %}
{% macro chunk(count, label) %}
{% set block = 32 if count % 32 == 0 else 16 %}
    SET LR10 CR0 ;;
    LD.MULT R0 LR5 {{ cr.w }} ; SET LR8 CR0 ; SET LR9 LR15 ;;
    INC LR5 1 ; INC LR10 {{ count // block }} ; DEC LR9 1 ;;
    LD.MULT R1 LR5 {{ cr.w }} ;;
    INC LR5 1 ;;
{{ label }}:
    LD.MULT.CYCLIC LR7 {{ cr.spatial }} LR0 ; INC LR7 {{ tiles }} ;;
{% for i in range(block) %}
    {{ mac(not loop.last) }}
{% endfor %}
    DEC LR10 1 ; BNE LR10 CR1 {{ label }} ;;
{% endmacro %}
gemm_init:
    SET LR0 CR0 ;;
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR6 CR0 ;;
    SET LR12 CR0 ; SET LR15 CR0 ;;
    INC LR12 {{ tiles }} ; INC LR15 128 ;;
channel:
    SET LR4 LR12 ; SET LR13 CR0 ;;
tile:
    SET LR5 LR3 ; SUB LR7 LR13 LR12 ; DEC LR4 1 ;;
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
    INC LR13 1 ; BEQ LR0 CR0 tile ;;
