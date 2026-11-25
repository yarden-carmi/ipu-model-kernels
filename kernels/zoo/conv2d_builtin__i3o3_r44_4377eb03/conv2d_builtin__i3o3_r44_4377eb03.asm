{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set chunks = (in0_d3 + 127) // 128 %}
{% set out_chunks = (out0_d3 + 127) // 128 %}
{% set pitch = stride * chunks %}
{% macro offset(reg, value) %}
{% for n in range(0, value | abs, 255) %}
    {{ 'INC' if value > 0 else 'DEC' }} {{ reg }} {{ [255, (value | abs) - n] | min }} ;;
{% endfor %}
{% endmacro %}

{# Convert each physical input line into zero-padded spatial rows. At stride
   two, gather even and odd samples separately so the MAC remains contiguous. #}
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR8 CR0 ;;
    INC LR8 128 ;;
prepare:
{% if stride == 1 %}
{% for c in range(chunks) %}
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR8 ;;
    MULT.RC.VE LR8 CR1 0 LR4 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR5 1 ;;
    ACTIVATE.QUANTIZE identity {{ cr.in_tail ~ '.L' if c == chunks-1 else full }} {{ qi }} {{ cr.clean }} LR6 ;;
    INC LR6 1 ;;
{% endfor %}
{% else %}
{% for p in range(stride) %}
{% for c in range(chunks) %}
    MULT.EE LR4 CR0 0 LR4 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; SET LR9 LR5 ;;
    {{ offset('LR9', c) }}
{% set count = (([128, in0_d3 - c*128] | min) + 1 - p) // 2 %}
{% if count %}
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR8 ;;
    SET LR0 {{ cr.src_lo }} ; SET LR1 {{ cr.src_hi }} ; INC LR9 1 ;;
    SET LR2 {{ cr.dst_lo }} ; SET LR3 {{ cr.dst_hi }} ; SET LR7 CR0 ;;
{% if p %}    ADDBI LRD0 {{ p }} ;;{% endif %}
{% if c == 0 %}    ADDBI LRD2 64 ;;{% endif %}
{% if count // 8 %}
    INC LR7 {{ count // 8 }} ;;
gather_{{ p }}_{{ c }}:
    MULT.RC.VE LR8 CR1 0 LR4 {{ full }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
    ADDBI LRD0 16 ; ADDBI LRD2 8 ; DEC LR7 1 ;;
    BLT.S LR4 LR7 gather_{{ p }}_{{ c }} ;;
{% endif %}
{% if count % 8 %}
    ADDBI LRD0 {{ 2 * (count % 8 - 8) }} ; ADDBI LRD2 {{ count % 8 - 8 }} ;;
    MULT.RC.VE LR8 CR1 0 LR4 {{ full }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 {{ 8 - count % 8 }} ;;
{% endif %}
{% endif %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.clean }} LR6 ;;
    INC LR6 1 ;;
{% endfor %}
{% endfor %}
    INC LR5 {{ chunks }} ;;
{% endif %}
    DEC LR13 1 ;;
    BLT.S LR4 LR13 prepare ;;

{# LR6 is the first input plane at the current (possibly padded) y.
   LR7 walks its valid tap rows, LR5 walks weight digits, and LR11 stores. #}
{% macro load_slot(slot, delta) %}
    SET LR1 CR0 ; SET LR4 LR7 ;;
    {{ offset('LR1', slot) }}
{% if stride == 1 and (delta < 0 or delta >= chunks) %}
    LD.MULT.CYCLIC LR0 {{ cr.weights }} LR1 ;;
{% else %}
    {{ offset('LR4', delta) }}
    LD.MULT.CYCLIC LR4 {{ cr.clean }} LR1 ;;
{% endif %}
{% endmacro %}

{% macro parity_slot(reg, p) %}
    SET {{ reg }} CR0 ; SET LR4 LR7 ;;
    {{ offset(reg, 256*p) }}
    {{ offset('LR4', p*chunks) }}
    LD.MULT.CYCLIC LR4 {{ cr.clean }} {{ reg }} ;;
    INC {{ reg }} 128 ;;
{% if chunks > 1 %}
    INC LR4 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.clean }} {{ reg }} ;;
{% else %}
    LD.MULT.CYCLIC LR0 {{ cr.weights }} {{ reg }} ;;
{% endif %}
    DEC {{ reg }} {{ 64 - ((p + padding) % stride - padding) // stride }} ;;
{% endmacro %}

{% macro tile(c) %}
    SET LR5 LR12 ; SET LR9 LR8 ; SET LR7 LR6 ;;
    INC LR9 {{ kh - 1 }} ; INC LR7 {{ (kh - 1) * pitch }} ;;
    SET LR10 CR0 ;;
    {{ offset('LR10', cin // groups) }}
{% if bias %}
    SET LR3 LR12 ; SET LR4 CR0 ;;
    LD.MULT R0 LR12 {{ cr.weights }} ; INC LR3 1 ; INC LR4 128 ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.weights }} ;;
    MULT.EE LR4 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT R1 LR3 {{ cr.weights }} ; INC LR3 1 ;;
    MULT.EE LR4 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
{% endif %}
ic_{{ c }}:
    LD.MULT R0 LR5 {{ cr.weights }} ;;
    INC LR5 2 ; SET LR2 CR1 ; SET LR3 CR1 ;;
    INC LR3 128 ;;
ky_{{ c }}:
    BLT.S LR9 CR0 skip_{{ c }} ;;
    SET LR4 CR0 ;;
    INC LR4 {{ in0_d2 }} ;;
    BGE.S LR9 LR4 skip_{{ c }} ;;
{% if stride == 1 %}
    {{ load_slot(0, c-1) }}
    {{ load_slot(256, c+1) }}
    {{ load_slot(128, c) }}
    {{ offset('LR1', -padding) }}
{% else %}
    {{ parity_slot('LR1', 0) }}
    {{ parity_slot('LR14', 1) }}
{% endif %}
    SUB LR4 LR3 CR1 ; LD.MULT R1 LR5 {{ cr.weights }} ;;
{% for x in range(kw) %}
{% set rc = 'LR14' if stride == 2 and (x-padding)%2 else 'LR1' %}
    MULT.RC.VE {{ rc }} LR4 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR4 1{% if x >= stride %} ; INC {{ rc }} 1{% endif %} ;;
{% endfor %}
    DEC LR1 {{ (kw if stride == 1 else (kw + 1 - padding % 2) // 2) - 1 }} ; SET LR4 LR5 ; DEC LR2 1 ;;
{% if stride == 2 and (kw + padding % 2) // 2 > 1 %}    DEC LR14 {{ (kw + padding % 2) // 2 - 1 }} ;;{% endif %}
    LD.MULT R1 LR4 {{ cr.weights }} ; DEC LR4 1 ; DEC LR3 1 ;;
{% for x in range(kw) %}
{% set rc = 'LR14' if stride == 2 and (x-padding)%2 else 'LR1' %}
    MULT.RC.VE {{ rc }} LR3 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR3 1 ; INC LR2 1{% if x >= stride %} ; INC {{ rc }} 1{% endif %} ;;
    MULT.RC.VE {{ rc }} LR2 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
{% endfor %}
    INC LR3 1 ; INC LR2 1 ;;
    BEQ LR0 CR0 next_{{ c }} ;;
skip_{{ c }}:
    INC LR2 {{ kw }} ; INC LR3 {{ kw }} ;;
next_{{ c }}:
    DEC LR9 1 ; DEC LR7 {{ pitch }} ;;
    BGE.S LR9 LR8 ky_{{ c }} ;;
    {{ offset('LR7', (kh - in0_d2) * pitch) }}
    SET LR9 LR8 ; DEC LR10 1 ; INC LR5 1 ;;
    INC LR9 {{ kh - 1 }} ;;
    BLT.S LR0 LR10 ic_{{ c }} ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.out_tail ~ '.L' if c == out_chunks-1 else full }} {{ qo }} {{ cr.out0 }} LR11 ;;
    INC LR11 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR6 CR0 ; SET LR11 CR0 ;;
    LD.MULT R0 LR0 {{ cr.weights }} ;;
{% if cin // groups > 1 %}
    SET LR10 CR0 ;;
    {{ offset('LR10', cin // groups - 1) }}
last_plane:
    {{ offset('LR6', in0_d2 * pitch) }}
    DEC LR10 1 ;;
    BLT.S LR0 LR10 last_plane ;;
{% endif %}
batch:
    SET LR12 CR1 ;;
group:
    SET LR13 CR0 ;;
    {{ offset('LR13', cout // groups) }}
channel:
    SET LR8 CR0 ;;
    {{ offset('LR8', -padding) }}
    {{ offset('LR6', -padding * pitch) }}
row:
{% for c in range(out_chunks) %}{{ tile(c) }}{% endfor %}
    INC LR8 {{ stride }} ; INC LR6 {{ stride * pitch }} ; SET LR4 CR0 ;;
    {{ offset('LR4', out0_d2 * stride - padding) }}
    BLT.S LR8 LR4 row ;;
    {{ offset('LR6', (padding - out0_d2 * stride) * pitch) }}
    SET LR12 LR5 ; DEC LR13 1 ;;
    BLT.S LR0 LR13 channel ;;
    SET LR14 CR0 ; SET LR10 CR0 ;;
    {{ offset('LR10', cin // groups) }}
advance_group:
    {{ offset('LR14', in0_d2 * pitch) }}
    DEC LR10 1 ;;
    BLT.S LR0 LR10 advance_group ;;
    ADD LR6 LR6 LR14 ;;
    BLT.S LR12 {{ cr.weight_rows }} group ;;
    DEC LR15 1 ;;
    BLT.S LR0 LR15 batch ;;
    HALT ;;
