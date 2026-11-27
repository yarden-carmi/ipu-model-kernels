{% set C = in0_d2 %}
{% set D = out0_d2 %}
{% set S = 4 * out0_d1 %}
{% set W = (D + 127) // 128 %}
{% set V = (C + 127) // 128 %}
{% set P = C // 8 %}
{% set T = D // 8 %}
{% set pieces = 3 if S >= 128 else 2 %}
{% macro move(reg, n) %}
{% for i in range((n if n >= 0 else -n) // 255) %}
    {{ 'INC' if n > 0 else 'DEC' }} {{ reg }} 255 ;;
{% endfor %}
{% set n = n % 255 if n >= 0 else -((-n) % 255) %}
{% if n > 0 %}INC {{ reg }} {{ n }} ;{% elif n < 0 %}DEC {{ reg }} {{ -n }} ;{% endif %}
{% endmacro %}

// The view maps (a,b,c) to linear offset a + 4*b + S*c.
// Gather eight consecutive offsets at once, writing 8x8 tiles.
group:
    SET LR6 LR10 ; SET LR7 LR1 ; SET LR8 CR0 ;;
    SET LR12 CR0 ; SET LR15 CR0 ;;
    INC LR12 {{ D // 8 - 1 }} ; SET LR4 {{ cr.seq_lo }} ; SET LR5 {{ cr.seq_hi }} ;;
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
    SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ;
    {% if p >= 16 %}INC LR6 1 ;{% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 0 ;
    {% if b % 128 %}ADDBI LRD2 {{ b % 128 }} ;{% endif %}
    {{ move('LR6', delta) }} LD.MULT R0 LR6 {{ cr.in0 }} ; B gather_{{ next // 8 }} ;;
gather_{{ p }}:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 0 ;
    {{ move('LR6', delta) }} {% if prevshift %}ADDBI LRD2 {{ prevshift }} ;{% endif %} ADDBI LRD4 8 ;
    LD.MULT R0 LR6 {{ cr.in0 }} ; BNE LR4 {{ cr.last_dest }} gather_{{ next // 8 }} ;;
    // At the end of the tile, drain the already-loaded successor.
    {% set drainshift = next % 128 - b % 128 %}
    {% set after = (next + S) % C %}
    {% set drainstep = (next + S) // C * V - next // 128 %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 0 ;
    {% if drainshift %}ADDBI LRD2 {{ drainshift }} ;{% endif %} ADDBI LRD4 8 ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.tiles }} LR8 ;
    {{ move('LR6', drainstep) }} NOP ;;
    LD.MULT R0 LR8 {{ cr.tiles }} ; SET LR13 LR8 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB ;
    INC LR13 {{ T }} ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.tail }}.H {{ cr.tiles }} LR13 ;;
{% if pieces == 3 %}
    LD.MULT R0 LR13 {{ cr.tiles }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.tail }}.H ; ACC.SUB ;
    INC LR13 {{ T }} ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.tail }}.H {{ cr.tiles }} LR13 ;;
{% endif %}
    BLT.S LR8 LR12 prime_{{ after // 8 }} ; INC LR8 1 ; SET LR4 {{ cr.seq_lo }} ; SET LR5 {{ cr.seq_hi }} ;;
    B unpack ;;
{% endfor %}

{% macro transpose(first, count, qf) %}
    SET LR8 CR0 ; SET LR4 {{ cr.seq_lo }} ; SET LR5 {{ cr.seq_hi }} ;;
    {{ move('LR8', first) }} LD.MULT R0 LR8 {{ cr.tiles }} ;;
{% for i in range(count) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0 ;
    {% if not loop.first %}ADDBI LRD4 8 ;{% endif %}
    {% if not loop.last %}INC LR8 1 ; LD.MULT R0 LR8 {{ cr.tiles }} ;{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro chunk(first, count, mask) %}
    // Split staging retains the low bits needed when the operands cancel.
{% if pieces == 3 %}
    {{ transpose(first + 2 * T, count, cr.tail ~ '.H') }}
    SET LR6 CR0 ;;
    INC LR6 {{ 3 * T + 1 }} ; ACTIVATE.QUANTIZE identity {{ mask }} {{ cr.tail }}.H {{ cr.tiles }} LR6 ;;
{% endif %}
    {{ transpose(first + T, count, cr.tail ~ '.H') }}
    SET LR6 CR0 ;;
    INC LR6 {{ 3 * T }} ; ACTIVATE.QUANTIZE identity {{ mask }} {{ cr.tail }}.H {{ cr.tiles }} LR6 ;;
    {{ transpose(first, count, cr.qf_in0 ~ '.L') }}
    LD.MULT R0 LR6 {{ cr.tiles }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.tail }}.H ; ACC.ADD ;
{% if pieces == 3 %}
    INC LR6 1 ; LD.MULT R0 LR6 {{ cr.tiles }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.tail }}.H ; ACC.ADD ;
{% endif %}
    LD.MULT R0 LR13 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
{% endmacro %}

unpack:
    SET LR2 {{ cr.stride_lo }} ; SET LR3 {{ cr.stride_hi }} ; SET LR13 LR11 ;;
    SET LR9 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
    INC LR14 7 ; INC LR15 3 ;;
position:
{% if W == 2 %}
    {{ chunk(0, 16, 'CR15.L') }}
    INC LR13 1 ;;
{% endif %}
    {{ chunk((W - 1) * 16, (D - (W - 1) * 128) // 8, cr.tail ~ '.L') }}
    BEQ LR9 LR14 group_done ; ADDBI LRD2 1 ;;
    BEQ LR9 LR15 wrap_batch ; INC LR9 1 ;;
    {{ move('LR13', out0_d1 * W - (W - 1)) }} B position ;;
wrap_batch:
    {{ move('LR13', 1 - 3 * out0_d1 * W) }} B position ;;
group_done:
    SET LR12 CR0 ; SET LR14 CR0 ;;
    INC LR12 {{ P - 1 }} ; {{ move('LR14', (out0_d1 - 2) * W) }} NOP ;;
    BEQ LR11 LR14 finish ; INC LR11 {{ 2 * W }} ;;
    BEQ LR1 LR12 wrap_origin ; INC LR1 1 ;;
    B group ;;
wrap_origin:
    SET LR1 CR0 ; INC LR10 {{ V }} ; B group ;;
finish:
    HALT ;;
