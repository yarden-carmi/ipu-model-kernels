{% set q = cr.qf_in0 ~ '.L' %}
{% set oq = cr.qf_out0 ~ '.L' %}
{% set out_act = act_out0 | default('identity') %}
{% set full = 'CR15.L' %}
 {% set tail = cr.tail ~ '.L' %}
{% macro init(reg, n=0) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD', first=false, imm='CR1') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro clear() %}{{ vec(first=true,imm='CR0') }}{% endmacro %}
{% macro load(n, cyclic=false) %}
 SET LR1 CR0 ;;
 {% if cyclic %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }}{% endif %}{% if n %} ; INC LR1 {{ n }}{% endif %} ;;
{% endmacro %}
{# Consume contiguous residual planes while prefetching the next plane. #}
{% macro products(n, count, first=false, dual=false) %}
 {{ load(n) }}
 {% for p in range(count) %}
 MULT.RC.VV LR0 R{{ p % 2 }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first and loop.first %}.FIRST{% endif %}{% if not dual and not loop.last %} ; LD.MULT R{{ (p + 1) % 2 }} LR1 {{ cr.tmp }} ; INC LR1 1{% endif %} ;;
 {% if dual %}
 MULT.RC.VV LR3 R{{ p % 2 }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if not loop.last %} ; LD.MULT R{{ (p + 1) % 2 }} LR1 {{ cr.tmp }} ; INC LR1 1{% endif %} ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
 {% macro split(reg, count) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% for p in range(count-1) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n, count=2) %}{{ init('LR1',n) }}{{ split('LR1',count) }}{% endmacro %}
{% macro average(label) %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {{ init('LR10') }}{{ init('LR7',3) }}{{ clear() }}
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.crow }} LR0 ;;
 {{ products(3,3) }}
 INC LR10 1 ;;
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro square_sum(ds) %}
 {% for a,b in [(0,0),(0,1),(1,1)] %}
 {% if a == b %}LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;{% endif %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for j in range(2 if a != b else 1) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 {% if a == b %}INC LR9 1 ;;{% endif %}
 {% endfor %}
{% endmacro %}

 {{ init('LR0') }}{{ init('LR2') }}{{ init('LR3',128) }}
row_loop:
 SET LR5 LR2 ; ADD LR6 LR2 {{ cr.K }} ;;
 {{ clear() }}
sum_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR5 1 ;;
 BLT.S LR5 LR6 sum_loop ;;
 {{ average('mean_scale') }}{{ save(6,3) }}

 SET LR5 LR2 ;;
 {{ init('LR9',32) }}
center_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 {{ vec(first=true) }}
 {% for n in range(6,9) %}{{ load(n) }}{{ vec('SUB') }}{% endfor %}
 {{ split('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ;;
 BLT.S LR5 LR6 center_loop ;;

 {{ clear() }}
 {{ init('LR9',32) }}
 ADD LR5 LR2 CR1 ;;
 BGE.S LR5 LR6 variance_tail ;;
variance_loop:
 {{ square_sum(full) }}
 INC LR5 1 ;;
 BLT.S LR5 LR6 variance_loop ;;
variance_tail:
 {{ square_sum(tail) }}
 {{ average('variance_scale') }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ vec() }}
 {{ init('LR1',12) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(9,3) }}
 {{ init('LR1',13) }}{{ clear() }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ init('LR4',2) }}
refine:
 {# Newton step: y <- 1.5*y - 0.5*v*y^3. #}
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 {{ products(12,2,first=(i==0)) }}
 {% endfor %}
 {{ save(14) }}
 {% for i in range(3) %}
 {{ load(9+i,true) }}
 {{ products(14,2,first=(i==0)) }}
 {% endfor %}
 {{ save(16) }}
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 {{ products(16,2,first=(i==0)) }}
 {% endfor %}
 {{ save(18) }}
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [18,19] %}{{ load(n) }}{{ vec('SUB',imm=cr.half) }}{% endfor %}
 {{ save(12) }}
 DEC LR4 1 ;;
 BLT.S CR0 LR4 refine ;;

 SET LR5 LR2 ;;
 {{ init('LR9',32) }}{{ init('LR11') }}
normalize:
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {{ products(12,2,first=loop.first) }}
 {% if not loop.last %}ADD LR10 LR10 {{ cr.K }} ;;{% endif %}
 {% endfor %}
 {{ save(20,3) }}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 INC LR9 1 ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;;
 INC LR9 1 ;;
 {{ products(20,3,first=true,dual=true) }}
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 {% if loop.first %}LD.MULT R0 LR10 {{ cr.beta }} ;;{% endif %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if not loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.beta }}{% endif %} ;;
 {% endfor %}
 {# The output is channel-lane, so the affine result needs no staging or transpose. #}
 ACTIVATE.QUANTIZE {{ out_act }} {{ full }} {{ oq }} {{ cr.out0 }} LR5 ;;
 INC LR5 1 ; INC LR11 1 ;;
 BLT.S LR5 LR6 normalize ;;
 SET LR2 LR6 ;;
 BLT.S LR2 LR13 row_loop ;;
 HALT ;;
 {% if false %}

{% if packed %}
 {# Pack both full-tile planes in 32-row blocks. Four channels
    occupy the two column parities of the two 16-lane row parities. #}
 SET LR0 LR13 ; ADD LR2 LR13 LR13 ;;
 ADD LR2 LR2 LR2 ;;
 {{ init('LR3',17) }}
 {% for byte in [16,1,0] %}
 {% for bit in range(8) %}ADD LR3 LR3 LR3 ;;{% endfor %}
 {% if byte %}INC LR3 {{ byte }} ;;{% endif %}
 {% endfor %}
 pack_plane:
 SET LR1 LR0 ; SET LR8 LR12 ;;
 pack_block:
 SET LR9 LR14 ; SET LR5 LR15 ; SET LR4 CR0 ;;
pack_group:
 SET LR10 LR1 ; SET LR7 LR3 ; SET LR11 CR0 ;;
 INC LR11 4 ; SET LR6 CR0 ;;
pack_octet:
 {% for i in range(8) %}
 {% if loop.first %}LD.MULT R0 LR10 {{ cr.normalized }} ;;{% endif %}
 {% if not loop.first %}ADDBI LRD6 2 ; {% endif %}MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD4 LRD6 4 ; ADD LR10 LR10 {{ cr.K }}{% if not loop.last %} ; LD.MULT R0 LR10 {{ cr.normalized }}{% endif %} ;;
 {% endfor %}
 ADDBI LRD6 18 ; DEC LR11 1 ;;
 BLT.S CR0 LR11 pack_octet ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ pq }} {{ cr.normalized }} LR2 ;;
 BNE LR0 CR0 pack_no_error ; LD.MULT R0 LR2 {{ cr.normalized }} ; ADD LR7 LR2 LR13 ;;
 ADD LR7 LR7 LR13 ; MULT.VE LR0 CR1 0 LR0 {{ full }} {{ pq }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ pq }} {{ cr.normalized }} LR7 ;;
 LD.MULT R0 LR7 {{ cr.normalized }} ;;
 ADD LR7 LR7 LR13 ; MULT.VE LR0 CR1 0 LR0 {{ full }} {{ pq }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ pq }} {{ cr.normalized }} LR7 ;;
 pack_no_error:
 INC LR2 1 ; ADDBI LRD4 4 ; DEC LR9 4 ;;
 SET LR6 CR0 ; INC.MODP2 LR4 CR0 8 ;;
 INC LR6 128 ;;
 BLT.S LR4 LR6 pack_group ;;
 BEQ LR9 CR0 pack_block_end ;;
 INC LR1 1 ; SET LR5 LR15 ; SET LR4 CR0 ; BEQ CR0 CR0 pack_group ;;
pack_block_end:
 SUB LR1 LR10 {{ cr.K }} ; DEC LR8 32 ;;
 INC LR1 1 ;;
 SET LR7 CR0 ;;
 INC LR7 32 ;;
 BGE.S LR8 LR7 pack_block ;;
 BEQ LR0 CR0 pack_planes_done ;;
 SET LR0 CR0 ; ADD LR2 LR13 LR13 ;;
 ADD LR2 LR2 LR13 ; BEQ CR0 CR0 pack_plane ;;
 pack_planes_done:
 SET LR0 CR0 ;;
 {{ init('LR3',128) }}
 {# Count four-channel groups in the output traversal. #}
 SET LR8 LR14 ; SET LR14 CR0 ;;
pack_count:
 DEC LR8 4 ; INC LR14 1 ;;
 BLT.S CR0 LR8 pack_count ;;
{% endif %}

 {# Transpose the leading value and its corrections before final output rounding. #}
{% macro scatter() %}
 MULT.EE LR4 CR1 0 LR15 {{ full }} {{ q }} ; ACC.RESHAPE LRD14 LRD10 7
{%- endmacro %}
{% macro gather(p) %}
 SET LR6 LR2 ; SET LR8 LR7 ;;
 {% for i in range(p) %}ADD LR6 LR6 LR13 ;;{% endfor %}
 {% if p == 2 %}
 BGE.S LR7 LR3 gather_start{{ p }} ;;
 MULT.VE LR15 CR0 0 LR15 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 {% endif %}
gather_start{{ p }}:
 {# Scatter the first row at slot zero. Peel the last row to avoid
    reading beyond the tile (or the allocation) in the pipelined loop. #}
 LD.MULT R0 LR6 {{ cr.normalized }} ; DEC LR8 2 ;;
 {{ scatter() }} ; ADD LR6 LR6 {{ cr.K }} ; BLT.S LR8 CR0 gather_done{{ p }} ;;
 LD.MULT R0 LR6 {{ cr.normalized }} ; BEQ LR8 CR0 gather_last{{ p }} ;;
gather{{ p }}:
 {{ scatter() }} ; LD.MULT R0 LR6 {{ cr.normalized }} ; ADDBI LRD10 1 ; ADD LR6 LR6 {{ cr.K }} ; DEC LR8 1 ; BLT.S CR1 LR8 gather{{ p }} ;;
gather_last{{ p }}:
 {{ scatter() }} ; ADDBI LRD10 1 ; ADD LR6 LR6 {{ cr.K }} ;;
gather_done{{ p }}:
{% endmacro %}

 {{ init('LR2') }}{{ init('LR15') }}
batch:
 SET LR4 CR0 ; SET LR1 LR2 ; SET LR9 CR0 ;;
channel:
 SET LR2 LR1 ; SET LR5 LR12 ;;
tile:
 SET LR7 LR3 ; SET LR10 CR0 ;;
 {% if packed %}
 BLT.S LR5 LR3 partial_tile ;;
 ADD LR11 LR13 LR13 ; SET LR7 {{ cr.K }} ;;
 ADD LR11 LR11 LR11 ; ADD LR7 LR7 LR7 ;;
 ADD LR11 LR11 LR13 ; ADD LR7 LR7 LR7 ;;
 ADD LR11 LR11 LR13 ;;
 SET LR8 CR0 ;;
 MULT.VE LR15 CR0 0 LR15 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR8 ;;
 INC LR8 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR8 ;;
 {% for i in range(3) %}ADD LR7 LR7 LR7 ;;{% endfor %}
 packed_gather:
 SUB LR6 LR2 LR1 ; SET LR8 CR0 ; SET LR10 CR0 ;;
 ADD LR6 LR6 LR9 ; INC.MODP2 LR8 LR4 2 ;;
 ADD LR6 LR6 LR11 ;;
 {% for h,v in [('on','on'),('on_inv','on'),('on','on_inv'),('on_inv','on_inv')] %}
 BEQ LR8 LR10 packed_lane{{ loop.index0 }}{% if not loop.last %} ; INC LR10 1{% endif %} ;;
 {% endfor %}
 {% for h,v in [('on','on'),('on_inv','on'),('on','on_inv'),('on_inv','on_inv')] %}
 packed_lane{{ loop.index0 }}:
 SET LR10 CR0 ; LD.MULT R0 LR6 {{ cr.normalized }} ;;
 {% for j in range(4) %}
 {% if not loop.first %}INC LR10 1 ; {% endif %}MULT.VE LR15 CR1 0 LR15 {{ full }} {{ pq }} ; ACC.STRIDE 16 {{ h }} {{ v }} LR10{% if not loop.last %} ; LD.MULT R0 LR6 {{ cr.normalized }} ; ADD LR6 LR6 LR7{% endif %} ;;
 {% endfor %}
 {% if not loop.last %}BEQ CR0 CR0 packed_gather_done ;;{% endif %}
 {% endfor %}
 packed_gather_done:
 ADD LR6 LR13 LR13 ; SET LR8 CR0 ;;
 ADD LR6 LR6 LR13 ;;
 BEQ LR11 LR6 packed_leading ; LD.MULT R0 LR8 {{ cr.tmp }} ; INC LR8 1 ;;
 MULT.VE LR15 CR1 0 LR15 {{ full }} {{ q }} ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.tmp }} ; DEC LR8 1 ;;
 MULT.VE LR15 CR1 0 LR15 {{ full }} {{ q }} ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR8 ; SUB LR11 LR11 LR13 ;;
 LD.MULT R0 LR8 {{ cr.tmp }} ;;
 MULT.VE LR15 CR1 0 LR15 {{ full }} {{ q }} ; ACC.SUB ; INC LR8 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR8 ; BEQ CR0 CR0 packed_gather ;;
 packed_leading:
 ADD LR6 LR7 LR7 ;;
 MULT.VE LR15 CR1 0 LR15 {{ full }} {{ q }} ; ACC.ADD ; DEC LR8 1 ; LD.MULT R0 LR8 {{ cr.tmp }} ; ADD LR6 LR6 LR6 ;;
 MULT.VE LR15 CR1 0 LR15 {{ full }} {{ q }} ; ACC.ADD ; ADD LR6 LR2 LR6 ; SET LR7 LR3 ; BEQ CR0 CR0 tile_store ;;
 partial_tile:
 SET LR7 LR5 ;;
 {% else %}
 BGE.S LR5 LR3 tile_ready ;;
 SET LR7 LR5 ;;
 {% endif %}
tile_ready:
 {# Partial tiles have a smaller dynamic range and need the extra residual. #}
 {% for p in [2,1,0] %}
 {% if p == 2 %}
 BLT.S LR7 LR3 low_plane ;;
 MULT.VE LR15 CR0 0 LR15 {{ full }} {{ q }} ; ACC.ADD.FIRST ; BEQ CR0 CR0 gather_done2 ;;
 low_plane:
 {% endif %}
 {{ gather(p) }}
 {% if not loop.first %}
 {% for r in range(2 if p == 0 else 1) %}
 {{ init('LR8',r) }}
 LD.MULT R0 LR8 {{ cr.tmp }} ;;
 MULT.VE LR15 CR1 0 LR15 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% endif %}
 {% if not loop.last %}
 {{ init('LR8') }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR8 ;;
 {% if p == 1 %}
 LD.MULT R0 LR8 {{ cr.tmp }} ;;
 MULT.VE LR15 CR1 0 LR15 {{ full }} {{ q }} ; ACC.SUB ; INC LR8 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR8 ;;
 {% endif %}
 {% endif %}
 {% endfor %}
 tile_store:
 ACTIVATE.QUANTIZE {{ out_act }} {{ full }} {{ oq }} {{ cr.out0 }} LR0 ;;
 INC LR0 1 ; SUB LR5 LR5 LR7 ;;
 SET LR2 LR6 ;;
 BLT.S CR0 LR5 tile ;;
 {% if packed %}
 INC.MODP2 LR4 CR1 7 ; SET LR8 CR0 ;;
 INC.MODP2 LR8 LR4 2 ;;
 BNE LR8 CR0 channel ;;
 INC LR9 1 ;;
 {% else %}
 INC LR9 1 ; INC.MODP2 LR4 CR1 7 ;;
 {% endif %}
 BNE LR4 CR0 same_chunk ;;
 INC LR1 1 ;;
same_chunk:
 BLT.S LR9 LR14 channel ;;
 SUB LR2 LR6 {{ cr.K }} ;;
 INC LR2 1 ;;
 BLT.S LR2 LR13 batch ;;
 HALT ;;
 {% endif %}
