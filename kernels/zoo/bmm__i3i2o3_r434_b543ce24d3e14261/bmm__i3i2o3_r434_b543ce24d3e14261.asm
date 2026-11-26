{% set chunks = (k+127)//128 %}
{% set tiled = k%32 == 0 and n%4 == 0 %}
{% macro increment(reg, amount) %}
{% if amount > 128 %} INC {{ reg }} 128 ;; {% endif %}
{% if amount %} INC {{ reg }} {{ amount if amount <= 128 else amount-128 }} ;; {% endif %}
{% endmacro %}
{# Scatter four neighboring columns in one pass over 32 keys. The
   four parity classes are the inverse of STRIDE 16's decimation. #}
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
{% macro tile_chunk(c) %}
{% set tiles = [128,k-128*c]|min // 32 %}
    SET LR9 CR0 ; SET LR10 CR0 ;;
    {{ increment('LR9', n*chunks+c*4) }}
    SET LR10 LR9 ;;
    {% if tiles > 1 %} INC LR10 {{ tiles-1 }} ;; {% endif %}
tile_{{ c }}:
    LD.MULT R0 LR8 {{ cr.vbase }} ;;
{% for key in range(32) %}
    ADD LR8 LR8 {{ cr.brows }} ;
    {% if not loop.last %} LD.MULT R0 LR8 {{ cr.vbase }} ; {% endif %}
    {% if key %} ADDBI LRD14 {{ 18 if key%8 == 0 else 2 }} ; {% endif %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.lane }}.H {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD10 LRD14 4 ;
    {% if loop.last %} ACTIVATE.QUANTIZE identity {{ cr.lane }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR9 ; {% endif %} ;;
{% endfor %}
    ADDBI LRD14 -110 ; INC LR9 1 ; BLT.S LR9 LR10 tile_{{ c }} ;;
{% endmacro %}
{% macro merge_tiles() %}
{% for col in range(4) %}
{% for c in range(chunks) %}
{% set tiles = [128,k-128*c]|min // 32 %}
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
{% endmacro %}
{% macro gather(c) %}
    SET LR9 CR0 ; SET LR15 CR0 ;;
{% if k-128*c > 1 %}
    {% set limit = [128,k-128*c]|min - 3 %}
    LD.MULT R0 LR8 {{ cr.vbase }} ; DEC LR9 1 ; {{ 'DEC LR15 1' if limit < 0 else 'INC LR15 ' ~ limit }} ;;
gather_{{ c }}:
    MULT.EE LR10 CR1 0 LR0 {{ cr.emit }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR9 {{ cr.emit }}.H ; LD.MULT R0 LR8 {{ cr.vbase }} ; INC LR9 1 ; ADD LR8 LR8 {{ cr.brows }} ; BLT.S LR9 LR15 gather_{{ c }} ;;
{% else %}
    LD.MULT R0 LR8 {{ cr.vbase }} ;;
{% endif %}
    MULT.EE LR10 CR1 0 LR0 {{ cr.emit }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR9 {{ cr.emit }}.H ; ADD LR8 LR8 {{ cr.brows }} {% if k-128*c > 1 %}; INC LR9 1 {% endif %};;
    ACTIVATE.QUANTIZE identity {{ cr.dots }}.{{ 'L' if c==0 else 'H' }} {{ cr.qf_in1 }}.L {{ cr.panel }} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}
{% macro dot(tail) %}
{% for c in range(chunks) %}
    MULT.RC.VV {{ 'LR0' if c==0 else 'LR12' }} R0 0 LR0 {{ cr.dots }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if c==0 else '' }} LR9 {{ cr.dots }}.{{ 'L' if c==0 else 'H' }} {% if c==0 %}; INC LR9 1 ; INC LR10 1 {% endif %};;
    MULT.RC.VV {{ 'LR13' if c==0 else 'LR14' }} R0 0 LR0 {{ cr.dots }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if c==0 else '' }} LR10 {{ cr.dots }}.{{ 'L' if c==0 else 'H' }}
    {% if not tail or not loop.last %}; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.panel }} {% endif %}
    {% if not tail and loop.last %}; BLT.S LR10 LR15 dot_column {% endif %}
    {% if tail and loop.last %}; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.emit }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 {% endif %};;
{% endfor %}
{% endmacro %}
group:
    SET LR2 LR1 ; SET LR3 {{ cr.lane }}.L ; SET LR4 {{ cr.head_pairs }}.L ;;
head:
{% if tiled %}
    SET LR10 LR3 ;;
    INC.MODP2 LR10 CR0 2 ;;
    BNE LR10 CR0 scalar_panel ;;
    SET LR7 CR0 ; SET LR12 LR3 ; SET LR13 LR2 ;;
    {{ bytes('LR15', [0,1,16,17]) }}
    {{ bytes('LR11', [0,1,2,3]) }}
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
    SET LR12 CR0 ; SET LR14 CR0 ; SET LR13 CR0 ;;
    INC LR12 128 ; SET LR11 {{ cr.head_pairs }}.H ; INC LR14 128 ;;
    INC LR13 128 ; INC LR14 128 ;;
    INC LR13 128 ; INC LR14 128 ;;
pair:
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
{% if chunks == 2 %}
    INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR12 ;;
{% endif %}
    INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR13 ;;
{% if chunks == 2 %}
    INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR14 ;;
{% endif %}
    INC LR5 1 ; SET LR7 CR0 ; SET LR9 CR0 ;;
    SET LR10 CR0 ;;
    SET LR15 CR0 ;;
    DEC LR9 1 ; INC LR10 {{ n-1 }} ; INC LR15 {{ 2*n-2 }} ; LD.MULT R0 LR7 {{ cr.panel }} ;;
{% if n > 1 %}
dot_column:
    {{ dot(false) }}
{% endif %}
    {{ dot(true) }}
    INC LR6 1 ; DEC LR11 1 ;;
    BNE LR11 CR0 pair ;;
    DEC LR4 1 ;;
    BEQ LR4 CR0 next_group ;;
    INC LR3 {{ n }} ;;
    BLT.S LR3 LR12 head ;;
    DEC LR3 128 ; INC LR2 1 ; B head ;;
next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.total_rows }} group ;;
    HALT ;;
