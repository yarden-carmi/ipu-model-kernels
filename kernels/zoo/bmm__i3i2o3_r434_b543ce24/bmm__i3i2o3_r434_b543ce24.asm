{% if k == 16 and n == 60 %}
    DEC LR5 1 ; DEC LR6 1 ; INC LR14 128 ;;
    INC LR15 {{ 128-n }} ; INC LR12 128 ; INC LR7 128 ;;
    INC LR12 128 ; INC LR7 {{ 128-n }} ; INC LR10 {{ k }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.lane }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR10 ;;
    LD.MULT.CYCLIC LR10 {{ cr.panel }} LR0 ;;
short_group:
    SET LR2 LR1 ; SET LR3 {{ cr.lane }}.L ; SET LR4 {{ cr.head_pairs }}.L ;;
short_head:
    SET LR11 {{ cr.head_pairs }}.H ; SET LR13 LR3 ;;
    INC LR13 {{ n }} ;;
    {# Align the head once, rather than reloading both seam rows for each query. #}
    SET LR8 LR2 ; SET LR9 CR0 ; SET LR11 CR0 ;;
    INC LR11 {{ k-2 }} ; DEC LR9 1 ; BGT.S LR13 LR14 short_stage_cross ;;
{% macro short_stage(cross) %}
short_stage_{{ 'cross' if cross else 'single' }}:
    LD.MULT R0 LR8 {{ cr.vbase }} ; ADD LR10 LR8 CR1 ;;
    {% if cross %} LD.MULT R1 LR10 {{ cr.vbase }} ;; {% endif %}
    MULT.VE LR3 CR1 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.dots }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR9 ; ADD LR8 LR8 {{ cr.tile_config }}.L ; INC LR9 1 ; BLT.S LR9 LR11 short_stage_{{ 'cross' if cross else 'single' }} ;;
{% endmacro %}
    {{ short_stage(false) }}
    B short_staged ;;
    {{ short_stage(true) }}
short_staged:
    SET LR11 {{ cr.head_pairs }}.H ; SET LR13 CR0 ;;
    LD.MULT.CYCLIC LR13 {{ cr.panel }} LR14 ;;
short_pair:
{% for row in range(2) %}
    INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR8 CR0 ; SET LR9 CR0 ;;
{% for key in range(16) %}
    MULT.RC.VE {{ ('LR14' if row == 0 else 'LR15') if key == 0 else ('LR12' if row == 0 else 'LR7') }} LR9 0 LR0 {{ cr.lane }}.H {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if key == 0 and row == 0 else '' }} ; {% if key %} INC LR9 1 ; {% endif %} {% if not loop.last %} INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.panel }} LR12 ; {% endif %}
    {% if loop.last and row == 1 %} INC LR6 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.emit }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; DEC LR11 1 ; BGT.S LR11 CR1 short_pair ; {% endif %} ;;
{% endfor %}
{% endfor %}
    DEC LR4 1 ; INC LR3 {{ n }} ;;
    BEQ LR4 CR0 short_next_group ;;
    BLT.S LR3 LR14 short_head ;;
    DEC LR3 128 ; INC LR2 1 ; B short_head ;;
short_next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.total_rows }} short_group ;;
    HALT ;;
{% else %}
{% set chunks = (k+127)//128 %}
{% set tiled = (k%32 == 0 or k==16) and n%4 == 0 %}
{% set wide = tiled and k >= 64 and n*chunks+2*(k//16) <= 128 %}
{% set narrow_tail = wide and k%32 == 0 and n%8 == 4 and n >= 12 %}
{% macro increment(reg, amount) %}
{% if amount > 128 %} INC {{ reg }} 128 ;; {% endif %}
{% if amount %} INC {{ reg }} {{ amount if amount <= 128 else amount-128 }} ;; {% endif %}
{% endmacro %}
{# Eight columns per pass. Each 16-key tile uses the four stride parity
   classes in each half. Its rotated copy lets either half meet the next
   tile at the R0/R1 seam without permuting the reduction axis. #}
{% macro wide_panel() %}
    {{ bytes_pair('LR10', 'LR11', [0,1,2,3], [4,5,6,7]) }}
    {{ bytes_pair('LR14', 'LR15', [0,1,16,17], [64,65,80,81]) }}
    SET LR12 LR3 ; SET LR13 LR2 ; SET LR7 CR0 ;;
    DEC LR7 1 ;;
wide_columns:
    SET LR9 CR0 ; SET LR8 LR13 ;;
    INC LR9 {{ n*chunks-1 }} ; INC LR10 64 ; LD.MULT R0 LR8 {{ cr.vbase }} ;;
{% macro scatter_wide_keys() %}
{% for key in range(16) %}
    ADD LR8 LR8 {{ cr.tile_config }}.L ;
    {% if key == 0 %} INC LR9 1 ; DEC LR10 64 ; {% endif %}
    {% if key %} ADDBI LRD14 {{ 18 if key == 8 else 2 }} ; {% endif %}
    {% if not loop.last %} LD.MULT R0 LR8 {{ cr.vbase }} ; {% endif %}
    MULT.VE LR12 CR1 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD10 LRD14 0 ;
    {% if loop.last %} ACTIVATE.QUANTIZE identity {{ cr.lane }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR9 ; {% endif %} ;;
{% endfor %}
{% endmacro %}
{% if k == 256 or (k == 64 and n%8 == 0) %}
    {# Each seam reads only one half of its rotated tile: the upper
       half for even tiles, the lower half for odd tiles. Load just the
       source register that feeds that half. #}
{% macro rotate_half(prefetch, repeat=false) %}
    MULT.VE LR10 CR1 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.lane }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR9 ; INC LR9 1 ;
    {% if prefetch %} LD.MULT R0 LR8 {{ cr.vbase }} ; {% endif %}
    {% if repeat %} B wide_keys ; {% endif %} ;;
{% endmacro %}
wide_keys:
    {{ scatter_wide_keys() }}
    LD.MULT R1 LR9 {{ cr.panel }} ; ADDBI LRD14 -46 ; INC LR10 64 ;;
    {{ rotate_half(true) }}
    {{ scatter_wide_keys() }}
    LD.MULT R0 LR9 {{ cr.panel }} ; ADDBI LRD14 -46 ; INC LR10 64 ; BEQ LR9 {{ cr.tile_config }}.H wide_keys_done ;;
    {{ rotate_half(true, true) }}
wide_keys_done:
    {{ rotate_half(false) }}
{% else %}
wide_keys:
    {{ scatter_wide_keys() }}
    LD.MULT R0 LR9 {{ cr.panel }} ; ADDBI LRD14 -46 ; INC LR10 64 ;;
    LD.MULT R1 LR9 {{ cr.panel }} ; BEQ LR9 {{ cr.tile_config }}.H wide_keys_last ;;
{% macro rotate_wide(prefetch) %}
    MULT.VE LR10 CR1 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {% if prefetch %} LD.MULT R0 LR8 {{ cr.vbase }} ; {% endif %}
    ACTIVATE.QUANTIZE identity {{ cr.lane }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR9 ; INC LR9 1 {% if prefetch %}; B wide_keys {% endif %};;
{% endmacro %}
    {{ rotate_wide(true) }}
wide_keys_last:
    {{ rotate_wide(false) }}
{% endif %}
    SET LR8 CR0 ; DEC LR10 65 ; SET LR9 CR0 ;;
{% if k == 64 and n%8 == 0 %}
    {# A 64-key strip needs just two tile pairs. Keep both seams in RC
       while extracting the four stride classes, rather than reloading
       the tile rows for each output column. #}
{% for half in range(2) %}
    SET LR8 CR0 ; SET LR9 CR0 ;;
    INC LR9 {{ n + (1 if half == 0 else 0) }} ; LD.MULT.CYCLIC LR9 {{ cr.panel }} LR8 ;;
{% for step in ([1,3,1] if half == 0 else [3,1,3]) %}
    INC LR8 128 ; INC LR9 {{ step }} ; LD.MULT.CYCLIC LR9 {{ cr.panel }} LR8 ;;
{% endfor %}
    SET LR9 LR8 ; SET LR8 CR0 ;;
    DEC LR9 64 ; INC LR8 64 ;;
{% for col in range(4) %}
    MULT.RC.VE LR8 CR1 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ 'on_inv' if col%2 else 'on' }} {{ 'on_inv' if col>=2 else 'on' }} LR10 ; {{ 'INC LR10 1' if col == 0 and half == 0 else 'DEC LR10 1' }} ;;
    MULT.RC.VE LR9 CR1 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ 'on_inv' if col%2 else 'on' }} {{ 'on_inv' if col>=2 else 'on' }} LR10 ; INC LR10 1 ; INC LR7 1 ; ACTIVATE.QUANTIZE identity {{ cr.dots }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR7 ;;
{% endfor %}
{% endfor %}
{% elif k == 256 and n >= 8 %}
    {# Keep two adjacent tile pairs in the cyclic register. Reversing
       traversal between columns reuses the last two pairs immediately. #}
    SET LR13 CR0 ; SET LR14 CR0 ; INC LR0 128 ;;
    INC LR14 64 ; INC LR0 128 ;;
    INC LR0 64 ;;
{% set state = namespace(row=0, slot=-1, acc=3) %}
{% for half in range(2) %}
{% for c in range(2) %}
{% set base = n*chunks+16*c+1-half %}
{% set gap = 1+2*half %}
    {{ cache_load(state,base,0) }} ;;
    {{ cache_load(state,base+gap,1) }} ;;
    {{ cache_load(state,base+4,2) }} ;;
    {{ cache_load(state,base+4+gap,3) }} ;;
{% for col in range(4) %}
{% set step = 1 if col%2 == 0 else -1 %}
{% set start = 0 if step == 1 else 3 %}
{% for i in range(4) %}
{% set t = start+i*step %}
{% set slot = (t%2)*2 %}
    {% if i == 3 %}
    {{ cache_load(state,base+t*4+gap,slot+1) }} ;;
    {% endif %}
    MULT.RC.VE {{ 'LR0' if slot else 'LR14' }} CR1 0 LR13 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ;
    ACC.STRIDE 16 {{ 'on_inv' if col%2 else 'on' }} {{ 'on_inv' if col>=2 else 'on' }} LR10 ;
    {{ move_by('LR10', (t-state.acc+2)%4-2) }}
    {% set state.acc = t %}
    {% if i == 0 %} {{ cache_load(state,base+(t+2*step)*4,slot) }} ; {% endif %}
    {% if i == 1 %} {{ cache_load(state,base+(t+step)*4+gap,2-slot+1) }} ; {% endif %}
    {% if i == 2 %} {{ cache_load(state,base+(t+step)*4,2-slot) }} ; {% endif %}
    {% if i == 3 %}
    {{ move_by('LR7',-5 if c and col==0 else 2 if col else 1) }}
    ACTIVATE.QUANTIZE identity {{ cr.dots }}.{{ 'H' if c else 'L' }} {{ cr.qf_in1 }}.L {{ cr.panel }} LR7 ;
    {% endif %} ;;
{% endfor %}
{% endfor %}
{% endfor %}
{% endfor %}
    SET LR0 CR0 ; SET LR8 LR15 ; SET LR14 LR15 ;;
    ADDBI LRD14 -64 ;;
    SET LR15 LR8 ; BLT.S LR12 LR3 cache_wrapped ;;
    SET LR13 LR2 ; B cache_merged ;;
cache_wrapped:
    SET LR13 LR2 ;;
    INC LR13 1 ;;
cache_merged:
{% else %}
    INC LR8 64 ;;
{% for col in range(8) %}
    {% if col == 4 and n%8 and not narrow_tail %}
    SET LR9 CR0 ;;
    INC LR9 {{ n*chunks-1 }} ;;
    BEQ LR7 LR9 panel_ready ; SET LR9 CR0 ;;
    {% endif %}
{% for c in range(chunks) %}
    INC LR9 {{ n*chunks+c*16 + (1 if col < 4 else 0) }} ; LD.MULT R0 LR9 {{ cr.panel }} ;
    {% if col or c %} DEC LR10 {{ ([128,k-128*(c-1 if c else chunks-1)]|min)//32 }} ; {% endif %} ;;
{% for t in range([128,k-128*c]|min//32) %}
    INC LR9 {{ 1 if col < 4 else 3 }} ; LD.MULT R1 LR9 {{ cr.panel }} ;;
    MULT.VE LR8 CR1 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ 'on_inv' if col%2 else 'on' }} {{ 'on_inv' if col%4>=2 else 'on' }} LR10 ; INC LR10 1 ;
    {% if loop.last %} INC LR7 1 ; SET LR9 CR0 ; ACTIVATE.QUANTIZE identity {{ cr.dots }}.{{ 'L' if c==0 else 'H' }} {{ cr.qf_in1 }}.L {{ cr.panel }} LR7 ; {% else %} INC LR9 {{ 3 if col < 4 else 1 }} ; LD.MULT R0 LR9 {{ cr.panel }} ; {% endif %} ;;
{% endfor %}
{% endfor %}
{% endfor %}
{% endif %}
    SET LR8 CR0 ; SET LR9 CR0 ; INC LR12 8 ;;
    INC LR8 128 ; INC LR9 {{ (n-4 if narrow_tail else n)*chunks-1 }} ; {% if not (k == 256 and n >= 8) %} DEC LR10 {{ ([128,k-128*(chunks-1)]|min)//32-1 }} ; {% endif %} ;;
{% if narrow_tail %}
    BGE.S LR12 LR8 wide_columns_wrap ;;
    BEQ LR7 LR9 wide_tail ;;
    B wide_columns ;;
wide_columns_wrap:
    DEC LR12 128 ; INC LR13 1 ; BEQ LR7 LR9 wide_tail ;;
    B wide_columns ;;
wide_tail:
    {# The final four columns fill a 32-key tile directly. #}
    SET LR11 LR10 ; SET LR15 LR14 ; SET LR10 CR0 ;;
    SET LR8 LR13 ; ADDB LRD10 LR12 ;;
{% for c in range(chunks) %}
    {{ tile_chunk(c) }}
{% endfor %}
    {% if k == 256 and n >= 8 %}
        {{ merge_wide_tail() }}
    {% else %}
        {{ merge_tiles() }}
    {% endif %}
    B panel_ready ;;
{% else %}
    BEQ LR7 LR9 panel_ready ;;
    BLT.S LR12 LR8 wide_columns ;;
    DEC LR12 128 ; INC LR13 1 ; B wide_columns ;;
{% endif %}
{% endmacro %}
{% macro move_by(reg, delta) %}
    {% if delta %} {{ 'INC' if delta > 0 else 'DEC' }} {{ reg }} {{ delta|abs }} ; {% endif %}
{% endmacro %}
{% macro cache_load(state,row,slot) %}
    {{ move_by('LR9',row-state.row) }}
    {% if slot != state.slot %}
        {{ ['SET LR8 CR0','ADD LR8 LR14 LR14','SUB LR8 LR0 LR14','ADD LR8 LR0 LR14'][slot] }} ;
    {% endif %}
    LD.MULT.CYCLIC LR9 {{ cr.panel }} LR8
    {% set state.row = row %}
    {% set state.slot = slot %}
{% endmacro %}
{# The tail's four 32-key tiles fit in RC. Extract all four column
   classes before replacing them with the next chunk. #}
{% macro merge_wide_tail() %}
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR10 CR0 ;;
    INC LR8 128 ; INC LR9 {{ n*chunks }} ; LD.MULT.CYCLIC LR9 {{ cr.panel }} LR0 ;;
    SET LR11 LR8 ; SET LR14 LR8 ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.panel }} LR8 ;;
    INC LR11 128 ; INC LR14 128 ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.panel }} LR11 ;;
    INC LR14 128 ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.panel }} LR14 ;;
{% for c in range(2) %}
{% for col in range(4) %}
{% for slot in ['LR0', 'LR8', 'LR11', 'LR14'] %}
    MULT.RC.VE {{ slot }} CR1 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ;
    ACC.STRIDE 16 {{ 'on_inv' if col%2 else 'on' }} {{ 'on_inv' if col>=2 else 'on' }} LR10 ;
    {% if c or col or not loop.first %} INC LR10 1 ; {% endif %}
    {% if c == 0 and col == 3 %} INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.panel }} {{ slot }} ; {% endif %}
    {% if loop.last %}
        {{ 'DEC LR7 5' if c and col == 0 else 'INC LR7 ' ~ (1 if c == 0 and col == 0 else 2) }} ;
        ACTIVATE.QUANTIZE identity {{ cr.dots }}.{{ 'H' if c else 'L' }} {{ cr.qf_in1 }}.L {{ cr.panel }} LR7 ;
    {% endif %} ;;
{% endfor %}
{% endfor %}
{% endfor %}
{% endmacro %}
{# Construct an LRD half from four byte indices, least significant first. #}
{% macro bytes_pair(a, b, av, bv) %}
    SET {{ a }} CR0 ; SET {{ b }} CR0 ;;
{% for i in range(3,-1,-1) %}
{% if not loop.first %}
{% for bit in range(8) %}
    ADD {{ a }} {{ a }} {{ a }} ; ADD {{ b }} {{ b }} {{ b }} ;;
{% endfor %}
{% endif %}
    {% if av[i] or bv[i] %}
    {% if av[i] %} INC {{ a }} {{ av[i] }} ; {% endif %}
    {% if bv[i] %} INC {{ b }} {{ bv[i] }} ; {% endif %} ;;
    {% endif %}
{% endfor %}
{% endmacro %}
{% macro bytes(reg, values) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ values[3] }} ;;
{% for byte in values[:3]|reverse %}
{% for bit in range(8) %}
    ADD {{ reg }} {{ reg }} {{ reg }} ;;
{% endfor %}
{% if byte %}
    INC {{ reg }} {{ byte }} ;;
{% endif %}
{% endfor %}
{% endmacro %}
{# Four-column scatter for the short-K path. The four parity classes
   are the inverse of STRIDE 16's decimation. #}
{% macro tile_chunk(c) %}
{% set keys = [128,k-128*c]|min %}
{% set tiles = (keys+31)//32 %}
    SET LR9 CR0 ; SET LR10 CR0 ;;
    {{ increment('LR9', n*chunks+c*4) }}
    SET LR10 LR9 ;;
    {% if tiles > 1 %} INC LR10 {{ tiles-1 }} ;; {% endif %}
tile_{{ c }}:
    {% if k==16 %} MULT.VE LR0 CR0 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;; {% endif %}
    LD.MULT R0 LR8 {{ cr.vbase }} ;;
{% for key in range([keys,32]|min) %}
    ADD LR8 LR8 {{ cr.tile_config }}.L ;
    {% if not loop.last %} LD.MULT R0 LR8 {{ cr.vbase }} ; {% endif %}
    {% if key %} ADDBI LRD14 {{ 18 if key%8 == 0 else 2 }} ; {% endif %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD10 LRD14 4 ;
    {% if loop.last %} ACTIVATE.QUANTIZE identity {{ cr.lane }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR9 ; {% endif %} ;;
{% endfor %}
    ADDBI LRD14 {{ -46 if k==16 else -110 }} ; INC LR9 1 ; BLT.S LR9 LR10 tile_{{ c }} ;;
{% endmacro %}
{% macro merge_tiles() %}
{% if k == 16 %}
    SET LR9 CR0 ; SET LR10 CR0 ;;
    {{ increment('LR9', n*chunks) }}
    LD.MULT R0 LR9 {{ cr.panel }} ;;
{% for col in range(4) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ 'on_inv' if col%2 else 'on' }} {{ 'on_inv' if col>=2 else 'on' }} LR10 ;
    INC LR7 1 ; ACTIVATE.QUANTIZE identity {{ cr.dots }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR7 ;;
{% endfor %}
{% else %}
{% for col in range(4) %}
{% for c in range(chunks) %}
{% set tiles = ([128,k-128*c]|min+31)//32 %}
    SET LR9 CR0 ; SET LR10 CR0 ;;
    {{ increment('LR9', n*chunks+c*4) }}
    LD.MULT R0 LR9 {{ cr.panel }} ;;
{% for t in range(tiles) %}
    {% if not loop.last %} INC LR9 1 ; LD.MULT R0 LR9 {{ cr.panel }} ; {% endif %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ 'on_inv' if col%2 else 'on' }} {{ 'on_inv' if col>=2 else 'on' }} LR10 ;
    {% if loop.last %} INC LR7 1 ; ACTIVATE.QUANTIZE identity {{ cr.dots }}.{{ 'L' if c==0 else 'H' }} {{ cr.qf_in1 }}.L {{ cr.panel }} LR7 ; {% endif %} ;;
    {% if not loop.last %} INC LR10 1 ;; {% endif %}
{% endfor %}
{% endfor %}
{% endfor %}
{% endif %}
{% endmacro %}
{% macro gather(c) %}
    SET LR9 CR0 ; SET LR15 CR0 ;;
{% if k-128*c > 1 %}
    {% set limit = [128,k-128*c]|min - 3 %}
    LD.MULT R0 LR8 {{ cr.vbase }} ; DEC LR9 1 ; {{ 'DEC LR15 1' if limit < 0 else 'INC LR15 ' ~ limit }} ;;
gather_{{ c }}:
    MULT.EE LR10 CR1 0 LR0 {{ cr.emit }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR9 {{ cr.emit }}.H ; LD.MULT R0 LR8 {{ cr.vbase }} ; INC LR9 1 ; ADD LR8 LR8 {{ cr.tile_config }}.L ; BLT.S LR9 LR15 gather_{{ c }} ;;
{% else %}
    LD.MULT R0 LR8 {{ cr.vbase }} ;;
{% endif %}
    MULT.EE LR10 CR1 0 LR0 {{ cr.emit }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR9 {{ cr.emit }}.H ; ADD LR8 LR8 {{ cr.tile_config }}.L {% if k-128*c > 1 %}; INC LR9 1 {% endif %};;
    ACTIVATE.QUANTIZE identity {{ cr.dots }}.{{ 'L' if c==0 else 'H' }} {{ cr.qf_in1 }}.L {{ cr.panel }} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}
{% macro dot(tail, first=false, cold=false) %}
{% for c in range(chunks) %}
    {% if not cold or c %}
    MULT.RC.VV {{ 'LR0' if c==0 else 'LR12' }} R0 0 LR0 {{ cr.dots }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if c==0 else '' }} LR9 {{ cr.dots }}.{{ 'L' if c==0 else 'H' }} {% if c==0 %}; INC LR9 1 ; INC LR10 1 {% endif %}
    {% if first %}; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} {{ 'LR13' if c==0 else 'LR14' }} {% endif %}
    {% if tail and n>1 and not cold %}
        {% if c==0 %}; BEQ LR11 CR1 tail_last_pair {% else %}; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 {% endif %}
    {% endif %};;
    {% endif %}
    MULT.RC.VV {{ 'LR13' if c==0 else 'LR14' }} R0 0 LR0 {{ cr.dots }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if c==0 else '' }} LR10 {{ cr.dots }}.{{ 'L' if c==0 else 'H' }}
    {% if not tail or not loop.last %}; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.panel }} {% endif %}
    {% if not first and not tail and loop.last %}; BLT.S LR10 LR15 dot_column {% endif %}
    {% if tail and loop.last %}; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.emit }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; INC LR6 1 ; DEC LR11 1
        {% if n==1 %}; BGT.S LR11 CR1 pair
        {% elif not cold %}; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} {{ 'LR12' if chunks==2 else 'LR0' }} ; B prefetched_pair
        {% endif %}
    {% endif %};;
{% endfor %}
{% endmacro %}
    DEC LR5 1 ; DEC LR6 1 ;;
group:
    SET LR2 LR1 ; SET LR3 {{ cr.lane }}.L ; SET LR4 {{ cr.head_pairs }}.L ;;
head:
{% if tiled %}
    SET LR10 LR3 ;;
    INC.MODP2 LR10 CR0 2 ;;
    BNE LR10 CR0 scalar_panel ;;
{% if wide %}
    SET LR10 LR3 ; SET LR9 LR3 ; SET LR8 CR0 ;;
    INC.MODP2 LR10 CR0 3 ; INC LR9 {{ n }} ; INC LR8 128 ;;
    BEQ LR10 CR0 wide_dispatch ;;
    BGT.S LR9 LR8 scalar_panel ;;
wide_dispatch:
    {{ wide_panel() }}
{% else %}
    SET LR7 CR0 ; SET LR12 LR3 ; SET LR13 LR2 ;;
    {{ bytes_pair('LR15', 'LR11', [0,1,16,17], [0,1,2,3]) }}
    SET LR10 CR0 ; DEC LR7 1 ;;
    ADDB LRD10 LR12 ;;
tile_columns:
    SET LR8 LR13 ;;
{% for c in range(chunks) %}
    {{ tile_chunk(c) }}
{% endfor %}
    {{ merge_tiles() }}
    SET LR10 CR0 ; SET LR9 CR0 ; INC LR12 4 ;;
    INC LR10 {{ n*chunks-1 }} ; INC LR9 128 ;;
    BEQ LR7 LR10 panel_ready ;;
    ADDBI LRD10 4 ; BLT.S LR12 LR9 tile_columns ;;
    ADDBI LRD10 -128 ; DEC LR12 128 ; INC LR13 1 ; B tile_columns ;;
{% endif %}
scalar_panel:
{% endif %}
    SET LR7 CR0 ; SET LR10 LR3 ; SET LR12 CR0 ;;
    SET LR13 LR2 ;;
    INC LR12 {{ n }} ;;
column:
    SET LR8 LR13 ;;
{% for c in range(chunks) %}
    {{ gather(c) }}
{% endfor %}
    INC LR10 1 ; DEC LR12 1 ;;
    BEQ LR12 CR0 panel_ready ;;
    SET LR15 CR0 ;;
    INC LR15 128 ;;
    BLT.S LR10 LR15 column ;;
    DEC LR10 128 ; INC LR13 1 ; B column ;;
panel_ready:
{% if (chunks == 2 or k == 64) and n > 1 %}
    SET LR12 CR0 ; SET LR14 CR0 ; SET LR13 CR0 ;;
    INC LR12 128 ; SET LR11 {{ cr.head_pairs }}.H ; INC LR14 128 ;;
    INC LR13 128 ; INC LR14 128 ; SET LR15 CR0 ;;
    INC LR13 128 ; INC LR14 128 ; INC LR15 {{ 2*n-2 }} ;;
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; SET LR7 CR0 ; {% if chunks == 1 %} SET LR9 CR0 ; {% endif %} ;;
    {% if chunks == 2 %} INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR12 ; SET LR9 CR0 ;; {% endif %}
    LD.MULT R1 LR7 {{ cr.panel }} ; INC LR9 {{ n }} ; SET LR10 CR0 ;;
    INC LR10 {{ 2*n-1 }} ; DEC LR9 1 ; DEC LR11 1 ; BEQ LR11 CR1 packed_first_last ;;
{% macro packed_dot(first=false, tail=false, last=false) %}
{% for c in range(chunks) %}
    MULT.RC.VV {{ 'LR0 R1' if c == 0 else 'LR12 R0' }} 0 LR0 {{ cr.dots }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if c == 0 else '' }} LR9 {{ cr.dots }}.{{ 'L' if c == 0 else 'H' }}
    {% if c == 0 %}; {{ 'DEC LR9 ' ~ (n-1) ~ ' ; DEC LR10 ' ~ (n-1) if first else 'INC LR9 1 ; INC LR10 1' }} {% endif %}
    {% if first or (tail and not last) %}; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} {{ (['LR13','LR14'] if first else ['LR0','LR12'])[c] }} {% endif %} ;;
    MULT.RC.VV {{ 'LR13 R1' if c == 0 else 'LR14 R0' }} 0 LR0 {{ cr.dots }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if c == 0 else '' }} LR10 {{ cr.dots }}.{{ 'L' if c == 0 else 'H' }}
    {% if not loop.last or not tail %}; INC LR7 1 ; LD.MULT {{ 'R0' if c == 0 and chunks == 2 else 'R1' }} LR7 {{ cr.panel }} {% endif %}
    {% if loop.last and tail %}; INC LR6 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.emit }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6
      {% if not last %}; DEC LR11 1 ; SET LR7 CR0 ; LD.MULT R1 LR7 {{ cr.panel }} ; BGT.S LR11 CR1 packed_first {% endif %}
    {% elif loop.last and not first %}; BLT.S LR10 LR15 packed_column{{ '_last' if last else '' }} {% endif %} ;;
{% endfor %}
{% endmacro %}
packed_first:
    {{ packed_dot(first=true) }}
{% if n > 2 %}
packed_column:
    {{ packed_dot() }}
{% endif %}
    {{ packed_dot(tail=true) }}
packed_first_last:
    {{ packed_dot(first=true,last=true) }}
{% if n > 2 %}
packed_column_last:
    {{ packed_dot(last=true) }}
{% endif %}
    {{ packed_dot(tail=true,last=true) }}
{% else %}
    SET LR12 CR0 ; SET LR14 CR0 ; SET LR13 CR0 ;;
    INC LR12 128 ; SET LR11 {{ cr.head_pairs }}.H ; INC LR14 128 ;;
    INC LR13 128 ; INC LR14 128 ; SET LR15 CR0 ;;
    INC LR13 128 ; INC LR14 128 ;;
    INC LR15 {{ 2*n-2 if n>1 else 1 }} ;;
pair:
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; SET LR10 CR0 ; SET LR9 CR0 ;;
{% if chunks == 2 %}
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR12 ; {% if n>1 %} INC LR10 {{ n-1 }} ; {% endif %} ;;
{% endif %}
    DEC LR9 1 ; SET LR7 CR0 ; LD.MULT R0 LR7 {{ cr.panel }} ; {% if chunks==1 and n>1 %} INC LR10 {{ n-1 }} ; {% endif %} ;;
{% if n > 1 %}
    B first_column ;;
prefetched_pair:
    {# The previous pair's last column left the next first query resident. #}
    DEC LR9 {{ n }} ; DEC LR10 {{ n }} ; SET LR7 CR0 ; LD.MULT R0 LR7 {{ cr.panel }} ;;
first_column:
    {# The first product also streams in the second query. #}
    {{ dot(false, true) }}
{% if n > 2 %}
dot_column:
    {{ dot(false) }}
{% endif %}
{% endif %}
    {{ dot(true, n==1) }}
{% if n > 1 %}
tail_last_pair:
    {{ dot(true, false, true) }}
{% endif %}
{% endif %}
    DEC LR4 1 ;;
    BEQ LR4 CR0 next_group ;;
    INC LR3 {{ n }} ;;
    BLT.S LR3 LR12 head ;;
    DEC LR3 128 ; INC LR2 1 ; B head ;;
next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.total_rows }} group ;;
    HALT ;;
{% endif %}
