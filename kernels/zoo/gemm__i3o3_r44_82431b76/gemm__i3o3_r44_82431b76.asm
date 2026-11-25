{% set tiny = in0_d2 * in0_d3 == 64 and k % 2 == 0 and in0_d0 == 1 and k <= 1024 %}
{% macro store(base, row, ds, qf, act='identity') %}ACTIVATE.QUANTIZE {{ act }} {{ ds }}.L {{ qf }}.L {{ base }} {{ row }}{% endmacro %}
{% macro out(row) %}{{ store(cr.out0,row,cr.lanes,cr.qf_out0,act_out0 | default('identity')) }}{% endmacro %}
{% macro coeff() %}INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR0{% endmacro %}
{% macro seed() %}
{% if bias %}
    {{ coeff() }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.lanes }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ coeff() }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.lanes }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% else %}
    {{ coeff() }} ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.lanes }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ coeff() }} ;;
{% endif %}
{% endmacro %}
{% if not tiny %}
{# Spatial SIMD: stream one activation row, then use both coefficient digits
   before advancing the input pointer. One coefficient pair covers 32 taps. #}
{% macro block(taps, final=false) %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ; SET LR1 CR0 ; SET LR2 {{ cr.second }} ;;
    INC LR7 1 ; LD.MULT R1 LR7 {{ cr.coeff }} ; DEC LR1 1 ; DEC LR2 1 ;;
{% for j in range(taps) %}
    MULT.RC.VE LR0 LR1 0 LR0 {{ cr.lanes }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR1 1 ;;
    MULT.RC.VE LR0 LR2 0 LR0 {{ cr.lanes }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR2 1{% if not final or not loop.last %} ; ADD LR6 LR6 LR4 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %}{% if not final and loop.last %} ; DEC LR14 1 ; BNE LR14 CR1 tap_block{% endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
    SET LR12 {{ cr.in0_d0 }} ;;
batch:
    SET LR8 {{ cr.n }} ; SET LR9 CR0 ;;
    DEC LR9 1 ;;
feature:
    SET LR10 LR11 ; SET LR13 LR4 ;;
spatial_row:
    SET LR7 LR9 ; SET LR6 LR10 ; SET LR14 {{ cr.repeat }} ;;
    {{ seed() }}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% if k > 32 %}
tap_block:
    {{ block(32) }}
{% endif %}
    {{ block((k-1)%32+1, true) }}
    {{ out('LR5') }} ;;
    INC LR5 1 ; INC LR10 1 ; DEC LR13 1 ; BNE LR13 CR1 spatial_row ;;
    SET LR9 LR7 ; DEC LR8 1 ; BNE LR8 CR1 feature ;;
    ADD LR11 LR11 LR15 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
{% else %}
{% set chunks = (k+127)//128 %}
{# Half-row images: interleave channel pairs into scratch, then gather
   pixel-major dot rows once and reuse them for every output feature. #}
{% macro gather(chunk, pairs) %}
    SET LR2 CR0 ; SET LR3 LR14 ; SET LR10 CR0 ;;
    LD.MULT R0 LR8 {{ cr.panel }} {% if pairs > 2 %}; INC LR10 {{ pairs-2 }}{% endif %} ;;
{% if pairs > 1 %}
    MULT.VE LR4 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 6 ; INC LR8 1 ; LD.MULT R0 LR8 {{ cr.panel }} ;;
{% if pairs > 2 %}
gather_{{ chunk }}:
    MULT.VE LR4 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 6 ; INC LR8 1 ; DEC LR10 1 ; ADDBI LRD2 2 ; LD.MULT R0 LR8 {{ cr.panel }} ; BNE LR10 CR1 gather_{{ chunk }} ;;
{% endif %}
{% endif %}
    MULT.VE LR4 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 6 ; INC LR8 1 {% if pairs > 1 %}; ADDBI LRD2 2{% endif %} ;;
    {{ store(cr.panel,'LR5',cr.active if chunk == chunks-1 else cr.full,cr.qf_in0) }} ;;
    INC LR5 1 ;;
{% endmacro %}
{% macro dot(pass) %}
    {{ coeff() }} ; SET LR10 LR12 ; SUB LR2 LR0 CR1 ;;
    LD.MULT R0 LR10 {{ cr.panel }} ; SET LR3 LR11 ;;
dot_{{ pass }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ cr.full }}.L ; INC LR10 {{ chunks }} ; INC LR2 1 ; DEC LR3 1 ; LD.MULT R0 LR10 {{ cr.panel }} ; BNE LR3 CR1 dot_{{ pass }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ cr.full }}.L ; INC LR2 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR8 CR0 ;;
    SET LR9 LR5 ; INC LR3 64 ; SET LR7 CR0 ;;
    DEC LR9 1 ;;
{% for j in range((k//2+127)//128) %}
    INC LR7 {{ [128,k//2-j*128] | min }} ;;
{% endfor %}
pack_pair:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    INC LR8 1 ; LD.MULT R1 LR8 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR8 1 ;;
    MULT.VE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1 ; DEC LR7 1 ; {{ store(cr.panel,'LR9',cr.full,cr.qf_in0) }} ; BNE LR7 CR1 pack_pair ;;
    SET LR13 LR5 ; SET LR5 CR0 ; SET LR1 LR6 ;;
    INC LR7 64 ; SET LR4 CR0 ;;
gather_pixel:
    SET LR8 LR13 ;;
{% for chunk in range(chunks) %}
    {{ gather(chunk, [64,k//2-64*chunk] | min) }}
{% endfor %}
    ADDBI LRD0 1 ; DEC LR7 1 ; BNE LR7 CR1 gather_pixel ;;
    SET LR0 CR0 ; SET LR7 CR0 ; SET LR6 CR0 ;;
    DEC LR7 1 ; SET LR13 {{ cr.n }} ; SET LR11 CR0 ;;
    INC LR11 63 ;;
tiny_feature:
    {{ seed() }}
    SET LR12 CR0 ;;
{% for chunk in range(chunks) %}
    {{ dot('coarse_' ~ chunk) }}
{% if bias or loop.last %}
    {{ dot('residual_' ~ chunk) }}
{% else %}
    {{ coeff() }} ;;
{% endif %}
{% if not loop.last %}
    INC LR12 1 ;;
{% endif %}
{% endfor %}
    {{ out('LR6') }} ;;
    INC LR6 1 ; DEC LR13 1 ; BNE LR13 CR1 tiny_feature ;;
    HALT ;;
{% endif %}
