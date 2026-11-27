{% set stride = (in0_d2 + 127) // 128 %}
{% set tokens = [in0_d1, 128 // in0_d0] | min %}
{% macro transpose_block(block, count) %}
    SET LR12 CR0 ; SET LR8 CR0 ; SET LR4 CR0 ;;
    INC LR12 {{ block }} ; INC LR4 {{ count }} ;;
feature_{{ block }}:
    SET LR9 {{ cr.width }} ; SET LR14 CR0 ; SET LR15 CR0 ;;
tile_{{ block }}:
    SET LR3 LR12 ; SET LR6 CR0 ; SET LR10 CR0 ;;
    SET LR11 CR0 ;;
{% if in0_d1 % tokens %}
    BEQ LR9 CR1 short_tile_{{ block }} ;;
    INC LR6 {{ tokens }} ; B token_{{ block }} ;;
short_tile_{{ block }}:
    INC LR6 {{ in0_d1 % tokens }} ;;
{% else %}
    INC LR6 {{ tokens }} ;;
{% endif %}
token_{{ block }}:
    SET LR2 LR3 ;;
{% for batch in range(in0_d0) %}
    LD.MULT R0 LR2 {{ cr.in0 }}{% if batch > 0 %} ; ADDBI LRD10 1{% endif %} ;;
    MULT.EE LR8 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD14 LRD10 7 ; ADD LR2 LR2 {{ cr.batch_step }} ;;
{% endfor %}
    INC LR3 {{ stride }} ; DEC LR6 1 ; ADDBI LRD10 1 ; BNE LR6 CR1 token_{{ block }} ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR13 ; INC LR13 1 ;;
    LD.MULT R0 LR13 {{ cr.panel }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.residual }} LR13 ;;
{% for part in range((tokens * stride + 126) // 127) %}
    INC LR12 {{ [127, tokens * stride - part * 127] | min }} ;;
{% endfor %}
    DEC LR9 1 ; BNE LR9 CR1 tile_{{ block }} ;;
    SET LR12 CR0 ; INC LR8 1 ; DEC LR4 1 ;;
    INC LR12 {{ block }} ; BNE LR4 CR0 feature_{{ block }} ;;
{% endmacro %}
{% macro mac(prefetch, base, branch='') %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1{% if prefetch %} ; LD.MULT.CYCLIC LR2 {{ base }} LR0 ; ADD LR2 LR2 {{ cr.width }}{% endif %}{{ branch }} ;;
{% endmacro %}
{% macro chunk(count, label, base) %}
    LD.MULT R0 LR4 {{ cr.w }} ; SET LR3 {{ cr.minusone }} ; INC LR4 1 ;;
    LD.MULT.CYCLIC LR2 {{ base }} LR0 ; ADD LR2 LR2 {{ cr.width }} ;;
{% if count == 128 %}
{{ label }}_group:
{% for i in range(31) %}
    {{ mac(true, base, ' ; BLT.S LR3 LR11 ' ~ label ~ '_advance' if i == 30 else '') }}
{% endfor %}
    {{ mac(false, base, ' ; DEC LR7 1 ; BNE LR7 CR1 ' ~ label ~ '_chunk') }}
    B {{ label }}_end ;;
{{ label }}_advance:
    {{ mac(true, base, ' ; B ' ~ label ~ '_group') }}
{{ label }}_end:
{% elif count > 1 %}
{{ label }}_lane:
    {{ mac(true, base, ' ; BLT.S LR3 LR12 ' ~ label ~ '_lane') }}
    {{ mac(false, base) }}
{% else %}
    {{ mac(false, base) }}
{% endif %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR13 {{ cr.minusone }} ;;
{% for block in range((k + 127) // 128) %}
    {{ transpose_block(block, [128, k - block * 128] | min) }}
{% endfor %}
    SET LR0 CR0 ; SET LR5 {{ cr.minusone }} ; SET LR6 {{ cr.minusone }} ;;
    SET LR10 {{ cr.n }} ; SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR11 125 ; {% if (k - 1) % 128 >= 2 %}INC LR12 {{ (k - 1) % 128 - 2 }}{% else %}DEC LR12 {{ 2 - (k - 1) % 128 }}{% endif %} ;;
channel:
    SET LR8 CR0 ; SET LR9 {{ cr.width }} ;;
tile:
    SUB LR2 LR8 {{ cr.width }} ; SET LR4 LR6 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR7 {{ cr.chunks }} ;;
{% if k >= 128 %}
full_chunk:
    {{ chunk(128, 'full', cr.panel) }}
{% endif %}
{% if k % 128 %}
    {{ chunk(k % 128, 'partial', cr.panel) }}
{% endif %}
    SUB LR2 LR8 {{ cr.width }} ; SET LR4 LR6 ; SET LR7 {{ cr.chunks }} ;;
    INC LR4 1 ;;
{% if k >= 128 %}
resfull_chunk:
    {{ chunk(128, 'resfull', cr.residual) }}
{% endif %}
{% if k % 128 %}
    {{ chunk(k % 128, 'respartial', cr.residual) }}
{% endif %}
    DEC LR9 1 ; BEQ LR9 CR1 last_tile ;;
    {{ store(cr.full) }}
    INC LR8 1 ; B tile ;;
last_tile:
    {{ store(cr.tail) }}
    SET LR6 LR4 ; DEC LR10 1 ; BNE LR10 CR1 channel ;;
    HALT ;;
