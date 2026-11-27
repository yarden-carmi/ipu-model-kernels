{% set C = in0_d2 %}
{% set D = out0_d2 %}
{% set S = 4 * out0_d1 %}
{% set W = (D + 127) // 128 %}
{% set V = (C + 127) // 128 %}
{% set P = C // 8 %}
{% set pieces = 3 if S >= 128 else 2 %}
{% macro move(reg, n) %}
{% for i in range((n if n >= 0 else -n) // 255) %}
    {{ 'INC' if n > 0 else 'DEC' }} {{ reg }} 255 ;;
{% endfor %}
{% set n = n % 255 if n >= 0 else -((-n) % 255) %}
{% if n > 0 %}INC {{ reg }} {{ n }} ;{% elif n < 0 %}DEC {{ reg }} {{ -n }} ;{% endif %}
{% endmacro %}

// Group eight adjacent offsets of the strided view. Gather each 8x8
// tile with one vector load and scatter per column, keeping base layouts.
group:
    SET LR6 LR10 ; SET LR7 LR1 ; SET LR8 CR0 ;;
    SET LR12 CR0 ;;
    {{ move('LR12', D // 8 - 1) }} NOP ;;
    SET LR15 CR0 ;;
{% for p in range(P - 1) %}
    BEQ LR7 LR15 prime_{{ p }} ; INC LR15 1 ;;
{% endfor %}
    B prime_{{ P - 1 }} ;;
{% for p in range(P) %}
    {% set b = p * 8 %}
    {% set next = (b + S) % C %}
    {% set delta = (b + S) // C * V + next // 128 - b // 128 %}
    {% set prev = (b - S) % C %}
    {% set prevshift = b % 128 - prev % 128 %}
prime_{{ p }}:
    SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ; SET LR4 {{ cr.seq_lo }} ;;
    SET LR5 {{ cr.seq_hi }} ;;
    {% if p >= 16 %}INC LR6 1 ;{% endif %}
    {% if b % 128 %}ADDBI LRD2 {{ b % 128 }} ;{% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 0 ;
    {{ move('LR6', delta) }} LD.MULT R0 LR6 {{ cr.in0 }} ; B gather_{{ next // 8 }} ;;
gather_{{ p }}:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 0 ;
    {{ move('LR6', delta) }} {% if prevshift %}ADDBI LRD2 {{ prevshift }} ;{% endif %} ADDBI LRD4 8 ;
    LD.MULT R0 LR6 {{ cr.in0 }} ; BNE LR4 {{ cr.last_dest }} gather_{{ next // 8 }} ;;
    B stash_{{ next // 8 }} ;;
stash_{{ p }}:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 0 ;
    {% if prevshift %}ADDBI LRD2 {{ prevshift }} ;{% endif %} ADDBI LRD4 8 ;
    {{ move('LR6', delta - next // 128) }}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.tiles }} LR8 ;
    NOP ;;
    LD.MULT R0 LR8 {{ cr.tiles }} ; SET LR15 LR8 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB ;
    INC LR15 {{ D // 8 }} ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.tail }}.H {{ cr.tiles }} LR15 ;;
{% if pieces == 3 %}
    LD.MULT R0 LR15 {{ cr.tiles }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.tail }}.H ; ACC.SUB ;
    INC LR15 {{ D // 8 }} ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.tail }}.H {{ cr.tiles }} LR15 ;;
{% endif %}
    BLT.S LR8 LR12 prime_{{ next // 8 }} ; INC LR8 1 ;;
    B unpack ;;
{% endfor %}

// Recover a contiguous output row from the tiles and add the whole-view
// operand in its own format before applying the output activation.
{% macro unpack_tiles(id, first, count, qf) %}
    SET LR8 CR0 ; SET LR12 CR0 ; SET LR4 {{ cr.seq_lo }} ;;
    SET LR5 {{ cr.seq_hi }} ; {{ move('LR8', first) }} ;;
    LD.MULT R0 LR8 {{ cr.tiles }} ; {{ move('LR12', first + count - 2 if count >= 2 else first) }} ;;
{% if count >= 2 %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0 ;
    INC LR8 1 ; LD.MULT R0 LR8 {{ cr.tiles }} ; BEQ LR8 LR12 unpack_last_{{ id }} ;;
unpack_{{ id }}:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0 ;
    INC LR8 1 ; ADDBI LRD4 8 ; LD.MULT R0 LR8 {{ cr.tiles }} ; BNE LR8 LR12 unpack_{{ id }} ;;
unpack_last_{{ id }}:
{% endif %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0
    {% if count >= 2 %}; ADDBI LRD4 8 {% endif %} ;;
{% endmacro %}
{% macro unpack_chunk(id, first, count, mask) %}
{% if pieces == 3 %}
    {{ unpack_tiles(id ~ '_err', first + D // 4, count, cr.tail ~ '.H') }}
    SET LR15 CR0 ;;
    INC LR15 {{ 3 * (D // 8) + 1 }} ; ACTIVATE.QUANTIZE identity {{ mask }} {{ cr.tail }}.H {{ cr.tiles }} LR15 ;;
{% endif %}
    {{ unpack_tiles(id ~ '_lo', first + D // 8, count, cr.tail ~ '.H') }}
    SET LR15 CR0 ;;
    INC LR15 {{ pieces * (D // 8) }} ; ACTIVATE.QUANTIZE identity {{ mask }} {{ cr.tail }}.H {{ cr.tiles }} LR15 ;;
    {{ unpack_tiles(id ~ '_hi', first, count, cr.qf_in0 ~ '.L') }}
    LD.MULT R0 LR15 {{ cr.tiles }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.tail }}.H ; ACC.ADD ;
{% if pieces == 3 %}
    INC LR15 1 ; LD.MULT R0 LR15 {{ cr.tiles }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.tail }}.H ; ACC.ADD ;
{% endif %}
    LD.MULT R0 LR13 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
{% endmacro %}
unpack:
    SET LR2 {{ cr.stride_lo }} ; SET LR3 {{ cr.stride_hi }} ; SET LR13 LR11 ;;
    SET LR9 CR0 ; SET LR14 CR0 ;;
    INC LR14 7 ;;
position:
{% if W == 2 %}
    {{ unpack_chunk('full', 0, 16, 'CR15.L') }}
    INC LR13 1 ;;
{% endif %}
    {{ unpack_chunk('tail', (W - 1) * 16, (D - (W - 1) * 128) // 8, cr.tail ~ '.L') }}
    BEQ LR9 LR14 group_done ; ADDBI LRD2 1 ;;
    SET LR15 CR0 ;;
    INC LR15 3 ;;
    BEQ LR9 LR15 wrap_batch ; INC LR9 1 ;;
    {{ move('LR13', out0_d1 * W - (W - 1)) }} B position ;;
wrap_batch:
    {{ move('LR13', W - 3 * out0_d1 * W - (W - 1)) }} B position ;;
group_done:
    SET LR12 CR0 ; SET LR14 CR0 ;;
    {{ move('LR12', P - 1) }} {{ move('LR14', (out0_d1 - 2) * W) }} NOP ;;
    BEQ LR11 LR14 finish ; INC LR11 {{ 2 * W }} ;;
    BEQ LR1 LR12 wrap_origin ; INC LR1 1 ;;
    B group ;;
wrap_origin:
    SET LR1 CR0 ; INC LR10 {{ V }} ; B group ;;
finish:
    HALT ;;
