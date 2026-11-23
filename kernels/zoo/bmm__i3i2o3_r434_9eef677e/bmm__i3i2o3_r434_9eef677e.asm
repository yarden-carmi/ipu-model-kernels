{# Each A row supplies 128 successive K scalars. Stream B vectors into
   the cyclic register, loading a second row only for a straddling tile. #}
    SET LR15 CR0 ; SET LR0 CR0 ; SET LR1 CR0 ;;
    INC LR15 128 ; SET LR13 CR0 ; SET LR14 CR0 ;;
group:
    SET LR2 LR1 ; SET LR3 CR0 ; SET LR4 {{ cr.mh }}.H ;;
head:
    BLE.S {{ cr.width }}.L LR15 transpose_head ;;
    SET LR5 {{ cr.mh }}.L ;;
row:
    SET LR6 LR2 ; SET LR7 {{ cr.width }}.L ;;
tile:
    SET LR8 LR0 ; SET LR9 LR6 ; SET LR10 {{ cr.k }} ;;
    MULT.VE LR14 CR0 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR11 LR7 ;;
    BLE.S LR11 LR15 width_ready ;;
    SET LR11 LR15 ;;
width_ready:
    ADD LR11 LR11 LR3 ;;
    BGT.S LR11 LR15 split_chunk ;;

{% macro reduce(tag, split) %}
{{ tag }}_chunk:
    SET LR12 LR10 ; SET LR11 CR0 ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
    INC LR8 1 ; BLE.S LR12 LR15 {{ tag }}_ready ;;
    SET LR12 LR15 ;;
{{ tag }}_ready:
    SUB LR10 LR10 LR12 ; DEC LR11 1 ;;
{% if split %}
{{ tag }}_inner:
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ; INC LR11 1 ;;
    INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR15 ;;
    DEC LR9 1 ;;
    MULT.RC.VE LR3 LR11 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; DEC LR12 1 ; ADD LR9 LR9 {{ cr.stride }}.L ; BGT.S LR12 CR1 {{ tag }}_inner ;;
{% else %}
{# Prime the cyclic slot, then replace its row in the same word that consumes
   it. LR12 counts the loads still to issue; drain without an out-of-range load. #}
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ; DEC LR12 1 ; BEQ LR12 CR1 {{ tag }}_last ;;
{{ tag }}_inner:
    MULT.RC.VE LR3 LR11 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ; INC LR11 1 ; ADD LR9 LR9 {{ cr.stride }}.L ; DEC LR12 1 ; BGT.S LR12 CR1 {{ tag }}_inner ;;
{{ tag }}_last:
    MULT.RC.VE LR3 LR11 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; INC LR11 1 ; ADD LR9 LR9 {{ cr.stride }}.L ;;
{% endif %}
    BNE LR10 CR0 {{ tag }}_chunk ;;
    B store ;;
{% endmacro %}
    {{ reduce('single', false) }}
    {{ reduce('split', true) }}

store:
    BGT.S LR7 LR15 full ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endmacro %}
    {{ output('H') }}
    ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR5 1 ; BGT.S LR5 CR1 row ;;
advance_head:
    DEC LR4 1 ; ADD LR3 LR3 {{ cr.width }}.L ;;
    BEQ LR4 CR0 next_group ;;
normalize:
    BLT.S LR3 LR15 head ;;
    DEC LR3 128 ; INC LR2 1 ; B normalize ;;
full:
    {{ output('L') }}
    DEC LR7 128 ; INC LR6 1 ; B tile ;;
next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.all_group_rows }} group ;;
    HALT ;;

{# Transpose one head into contiguous K vectors. Each scratch row is
   initialized, including the tail, before it is consumed by a dot product. #}
transpose_head:
    SET LR5 {{ cr.width }}.L ;;
    INC.MODP2 LR5 CR0 3 ;;
    BNE LR5 CR0 transpose_scalar ;;
    BEQ {{ cr.k }} LR15 transpose_tiles ;;
    SET LR5 LR15 ;;
    INC LR5 128 ;;
    BNE {{ cr.k }} LR5 transpose_scalar ;;
    B transpose_tiles ;;
transpose_scalar:
    SET LR5 {{ cr.width }}.L ; SET LR7 LR2 ; SET LR14 LR3 ;;
    SET LR6 CR0 ; SET LR8 CR0 ;;
transpose_column:
    SET LR11 LR7 ; SET LR10 {{ cr.k }} ;;
transpose_chunk:
    SET LR12 CR0 ; SET LR9 LR10 ; MULT.VE LR8 CR0 0 LR8 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    BLE.S LR9 LR15 transpose_count ;;
    SET LR9 LR15 ;;
transpose_count:
    SUB LR10 LR10 LR9 ; DEC LR9 1 ; DEC LR12 1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR8 ; DEC LR9 2 ; BEQ LR9 CR0 transpose_drain ;;
transpose_key:
    MULT.RC.VE LR14 CR1 0 LR8 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR12 {{ cr.width }}.H ; ADD LR11 LR11 {{ cr.stride }}.L ; LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR8 ; INC LR12 1 ; BLT.S LR12 LR9 transpose_key ;;
transpose_drain:
    MULT.RC.VE LR14 CR1 0 LR8 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR12 {{ cr.width }}.H ; ADD LR11 LR11 {{ cr.stride }}.L ; INC LR12 1 ; ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_in1 }}.L {{ cr.transposed }} LR6 ;;
    INC LR6 1 ; BNE LR10 CR0 transpose_chunk ;;
    DEC LR5 1 ; INC.MODP2 LR14 CR1 7 ;;
    BNE LR14 CR0 transpose_next_column ;;
    INC LR7 1 ;;
transpose_next_column:
    BNE LR5 CR0 transpose_column ;;

dot_setup:
    SET LR5 {{ cr.mh }}.L ; SET LR11 {{ cr.width }}.L ;;
    DEC LR11 2 ; SET LR12 CR1 ;;
    INC LR12 1 ;;
    BNE {{ cr.stride }}.H LR12 dot_generic ;;
    BLT.S LR11 CR1 dot_generic ;;
    B dot_pair_setup ;;
dot_generic:
    DEC LR11 1 ;;
dot_row:
    SET LR6 CR0 ; SET LR7 LR0 ; SET LR12 {{ cr.stride }}.H ;;
{% macro dots(tag, first) %}
{{ tag }}:
    SET LR9 LR6 ; SET LR10 CR0 ; LD.MULT R0 LR7 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR9 {{ cr.transposed }} LR8 ; DEC LR10 1 ; BLT.S LR11 LR10 {{ tag }}_last ;;
{{ tag }}_column:
    MULT.RC.VV LR8 R0 0 LR8 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR10 {{ cr.ds }}.L ; ADD LR9 LR9 {{ cr.stride }}.H ; LD.MULT.CYCLIC LR9 {{ cr.transposed }} LR8 ; INC LR10 1 ; BLT.S LR10 LR11 {{ tag }}_column ;;
{{ tag }}_last:
    MULT.RC.VV LR8 R0 0 LR8 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR10 {{ cr.ds }}.L ; INC LR10 1 ; INC LR6 1 ; INC LR7 1 ;;
    DEC LR12 1 ;;
{% endmacro %}
    {{ dots('dot_first', true) }}
    BEQ LR12 CR0 dot_store ;;
    {{ dots('dot_more', false) }}
    BNE LR12 CR0 dot_more ;;
dot_store:
    {{ output('H') }}
    ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR5 1 ; BGT.S LR5 CR1 dot_row ;;
    B advance_head ;;

{# Two K chunks: pin the first column's two B rows. Prime A0, then
   load A1 during the first product and keep both resident for the row.
   Stream the rest through a third cyclic slot, re-primed at the store. #}
dot_pair_setup:
    SET LR14 LR15 ; SET LR6 CR1 ;;
    INC LR14 128 ; DEC LR13 1 ;;
    LD.MULT.CYCLIC LR8 {{ cr.transposed }} LR8 ;;
    LD.MULT.CYCLIC LR6 {{ cr.transposed }} LR15 ;;
    LD.MULT.CYCLIC LR12 {{ cr.transposed }} LR14 ;;
{% macro pair_product(slot, ra, first) %}
    MULT.RC.VV {{ slot }} {{ ra }} 0 LR8 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR10 {{ cr.ds }}.L ;
{% endmacro %}
dot_pair_row:
    LD.MULT R0 LR0 {{ cr.in0 }} ; SET LR10 CR0 ; SET LR9 LR12 ; INC LR13 1 ;;
    {{ pair_product('LR8', 'R0', true) }} LD.MULT R1 LR0 {{ cr.in0 }} ; INC LR0 1 ;;
    {{ pair_product('LR15', 'R1', false) }} INC LR0 1 ;;
dot_pair_column:
    {{ pair_product('LR14', 'R0', true) }} LD.MULT.CYCLIC LR9 {{ cr.transposed }} LR14 ; INC LR9 1 ; INC LR10 1 ;;
    {{ pair_product('LR14', 'R1', false) }} LD.MULT.CYCLIC LR9 {{ cr.transposed }} LR14 ; INC LR9 1 ; BLT.S LR10 LR11 dot_pair_column ;;
    {{ pair_product('LR14', 'R0', true) }} LD.MULT.CYCLIC LR9 {{ cr.transposed }} LR14 ; INC LR9 1 ; INC LR10 1 ;;
    {{ pair_product('LR14', 'R1', false) }} LD.MULT.CYCLIC LR12 {{ cr.transposed }} LR14 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ; DEC LR5 1 ; BGT.S LR5 CR1 dot_pair_row ;;
    INC LR13 1 ; B advance_head ;;

{# Initialize consecutive or strided byte-index vectors. Build both halves
   in parallel using small immediates. #}
{% macro indices(step) %}
    SET LR10 CR0 ; SET LR11 CR0 ;;
{% set a = step * 50462976 %}
{% set b = step * 117835012 %}
{% for bit in range(30, -1, -1) %}
{% if (2 ** bit) <= b %}
    ADD LR10 LR10 LR10 ; ADD LR11 LR11 LR11 ;;
{% if (a // (2 ** bit)) % 2 or (b // (2 ** bit)) % 2 %}
    INC LR10 {{ (a // (2 ** bit)) % 2 }} ; INC LR11 {{ (b // (2 ** bit)) % 2 }} ;;
{% endif %}
{% endif %}
{% endfor %}
{% endmacro %}

{# Transpose 8x8 blocks, then concatenate their contiguous K segments.
   Width is divisible by eight, so no block crosses a source row.
   Scratch rows 0..255 hold the final vectors; tiles start at row 256. #}
transpose_tiles:
    {{ indices(1) }}
    SET LR8 LR10 ; SET LR9 LR11 ;;
    {# Reuse LR8 as the mask-shift operand. Its positive value clamps
       to three, so skip the first three lanes and bias the origin. #}
    ADDBI LRD8 3 ;;
    {{ indices(8) }}
    SET LR5 LR3 ; SET LR7 CR0 ; SET LR12 {{ cr.width }}.L ;;
    INC LR7 128 ; MULT.VE LR8 CR0 0 LR8 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    INC LR7 127 ;;
block_columns:
    SET LR6 LR2 ; SET LR14 {{ cr.k }} ; INC LR5 125 ;;
    SUB LR6 LR6 {{ cr.stride }}.L ;;
block_keys:
    LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR15 ; ADD LR6 LR6 {{ cr.stride }}.L ;;
{% for key in range(8) %}
{% if key > 0 %}
    ADDBI LRD10 1 ;
{% endif %}
    MULT.RC.VE LR5 CR1 0 LR8 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD8 LRD10 0 ;
{% if key < 7 %}
    LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR15 ; ADD LR6 LR6 {{ cr.stride }}.L ;;
{% else %}
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_in1 }}.L {{ cr.transposed }} LR7 ; INC LR7 1 ; DEC LR14 8 ;;
    ADDBI LRD10 -7 ; BNE LR14 CR0 block_keys ;;
{% endif %}
{% endfor %}
    DEC LR5 117 ; DEC LR12 8 ;;
    INC.MODP2 LR5 CR0 7 ;;
    BNE LR5 CR0 block_next ;;
    INC LR2 1 ;;
block_next:
    BNE LR12 CR0 block_columns ;;
    {# Restore the head's original address after crossing a row boundary. #}
    ADD LR5 LR3 {{ cr.width }}.L ;;
    BLT.S LR5 LR15 block_restore_done ;;
    DEC LR2 1 ;;
block_restore_done:
    {{ indices(1) }}
    SET LR5 CR0 ; SET LR7 CR0 ; SET LR12 {{ cr.width }}.L ;;
    INC LR7 128 ; INC LR5 128 ;;
    INC LR7 128 ;;
    SET LR8 CR0 ; SET LR9 CR0 ;;
    DEC LR9 1 ;;
gather_column:
    SET LR6 LR7 ; SET LR14 {{ cr.k }} ;;
    DEC LR6 1 ;;
gather_chunk:
    LD.MULT.CYCLIC LR6 {{ cr.transposed }} LR15 ; INC LR6 1 ;;
{# Reuse one index vector for both scatter operands: as the indices
   advance eight lanes, move the cyclic origin back by eight. #}
{% for tile in range(16) %}
{% if tile > 0 %}
    DEC LR5 8 ;;
    ADDBI LRD10 8 ;
{% endif %}
    MULT.RC.VE LR5 CR1 0 LR8 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD10 LRD10 0 ;
{% if tile < 15 %}
    LD.MULT.CYCLIC LR6 {{ cr.transposed }} LR15 ; INC LR6 1 ;;
{% else %}
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_in1 }}.L {{ cr.transposed }} LR9 ; INC LR9 1 ; DEC LR14 128 ;;
    ADDBI LRD10 -120 ; INC LR5 120 ; BNE LR14 CR0 gather_chunk ;;
{% endif %}
{% endfor %}
    INC LR5 8 ; DEC LR12 1 ;;
    BEQ LR12 CR0 gather_done ;;
    INC.MODP2 LR5 CR0 6 ;;
    BNE LR5 CR0 gather_next ;;
    SET LR7 LR6 ;;
    INC LR7 1 ;;
gather_next:
    INC LR5 128 ; B gather_column ;;
gather_done:
    B dot_setup ;;
