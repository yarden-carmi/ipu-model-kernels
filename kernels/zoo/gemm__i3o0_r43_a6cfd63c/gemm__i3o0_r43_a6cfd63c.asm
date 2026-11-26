{% macro mac(prefetch, branch='') %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1{% if prefetch %} ; LD.MULT.CYCLIC LR2 {{ cr.panel }} LR0 ; ADD LR2 LR2 {{ cr.width }}{% endif %}{{ branch }} ;;
{% endmacro %}
{% macro chunk(count, label) %}
    LD.MULT R0 LR4 {{ cr.w }} ; SET LR3 {{ cr.minusone }} ; INC LR4 1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.panel }} LR0 ; ADD LR2 LR2 {{ cr.width }} ;;
{% if count == 128 %}
{{ label }}_group:
{% for i in range(31) %}
    {{ mac(true, ' ; BLT.S LR3 ' ~ cr.last_full ~ ' ' ~ label ~ '_advance' if i == 30 else '') }}
{% endfor %}
    {{ mac(false, ' ; DEC LR7 1 ; BNE LR7 CR1 full_chunk') }}
    B {{ label }}_end ;;
{{ label }}_advance:
    {{ mac(true, ' ; B ' ~ label ~ '_group') }}
{{ label }}_end:
{% elif count > 1 %}
{{ label }}_lane:
    {{ mac(true, ' ; BLT.S LR3 ' ~ cr.last_tail ~ ' ' ~ label ~ '_lane') }}
    {{ mac(false) }}
{% else %}
    {{ mac(false) }}
{% endif %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
{# Transpose the packed feature input into feature-major sample panels. #}
{% if in0_d0 == 4 and in0_d1 == 4 and in0_d2 == 64 and in0_d3 == 48 and k == 192 and m == 256 %}
{% macro transpose_pass(suffix, base) %}
    SET LR12 {{ base }} ; SET LR8 CR0 ; SET LR4 CR0 ;;
    INC LR4 96 ;;
feature_panel_{{ suffix }}:
    SET LR9 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
panel_tile_{{ suffix }}:
    SET LR3 LR12 ; SET LR6 CR0 ; SET LR10 CR0 ;;
    SET LR11 CR0 ;;
    INC LR6 32 ;;
panel_token_{{ suffix }}:
    SET LR2 LR3 ;;
    DEC LR2 64 ;;
{% for batch in range(4) %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 64{% if batch > 0 %} ; ADDBI LRD10 1{% endif %} ;;
    MULT.EE LR8 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD14 LRD10 7 ; INC LR2 64 ;;
{% endfor %}
    INC LR3 2 ; DEC LR6 1 ; ADDBI LRD10 1 ; BNE LR6 CR1 panel_token_{{ suffix }} ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR13 ; INC LR13 1 ;;
    INC LR12 64 ; INC LR9 1 ; BLT.S LR9 CR1 panel_tile_{{ suffix }} ;;
    SET LR12 {{ base }} ; INC LR8 1 ; DEC LR4 1 ; BNE LR4 CR1 feature_panel_{{ suffix }} ;;
{% endmacro %}
    SET LR13 {{ cr.minusone }} ;;
    {{ transpose_pass('first', 'CR0') }}
    {{ transpose_pass('second', 'CR1') }}
{% endif %}
    SET LR0 CR0 ; SET LR5 {{ cr.minusone }} ; SET LR6 {{ cr.minusone }} ;;
    SET LR10 {{ cr.n }} ;;
channel:
    SET LR8 CR0 ; SET LR9 {{ cr.width }} ;;
tile:
    SUB LR2 LR8 {{ cr.width }} ; SET LR4 LR6 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR7 {{ cr.chunks }} ;;
{% if k >= 128 %}
full_chunk:
    {{ chunk(128, 'full') }}
{% endif %}
{% if k % 128 %}
    {{ chunk(k % 128, 'partial') }}
{% endif %}
    DEC LR9 1 ; BEQ LR9 CR1 last_tile ;;
    {{ store(cr.full) }}
    INC LR8 1 ; B tile ;;
last_tile:
    {{ store(cr.tail) }}
    SET LR6 LR4 ; DEC LR10 1 ; BNE LR10 CR1 channel ;;
    HALT ;;
