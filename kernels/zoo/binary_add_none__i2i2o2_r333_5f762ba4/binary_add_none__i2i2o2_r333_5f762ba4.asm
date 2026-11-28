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
{% macro gather_pick() %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 0 ;
{% endmacro %}

// Gather eight adjacent storage offsets for each group of eight channels.
group:
    SET LR6 LR10 ; SET LR8 CR0 ;;
    SET LR12 CR0 ; SET LR15 CR0 ; SET LR14 {{ cr.seq_lo }} ;;
    ADDBI LRD14 40 ;;
    SET LR15 CR0 ;;
    INC LR12 {{ T - 1 }} ; SET LR4 {{ cr.seq_lo }} ; SET LR5 {{ cr.seq_hi }} ;;
{% for p in range(P - 1) %}
    BEQ LR1 LR15 prime_{{ p }} ; INC LR15 1 ;;
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
    {{ gather_pick() }}
    {% if b % 128 %}ADDBI LRD2 {{ b % 128 }} ;{% endif %}
    {{ move('LR6', delta) }} LD.MULT R0 LR6 {{ cr.in0 }} ; B gather_{{ next // 8 }} ;;
gather_{{ p }}:
    {{ gather_pick() }}
    {{ move('LR6', delta) }} {% if prevshift %}ADDBI LRD2 {{ prevshift }} ;{% endif %} ADDBI LRD4 8 ;
    LD.MULT R0 LR6 {{ cr.in0 }} ; BNE LR4 LR14 gather_{{ next // 8 }} ;;
    {% set drainshift = next % 128 - b % 128 %}
    {% set after = (next + S) % C %}
    {% set drainstep = (next + S) // C * V - next // 128 %}
    {{ gather_pick() }}
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

{% macro transpose(count, qf) %}
{% for i in range(count) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0 ;
    {% if loop.first %}SET LR4 {{ cr.seq_lo }} ; SET LR5 {{ cr.seq_hi }} ;{% else %}ADDBI LRD4 8 ;{% endif %}
    {% if not loop.last %}INC LR8 1 ; LD.MULT R0 LR8 {{ cr.tiles }} ;{% endif %}
    {% if not loop.last %};;{% endif %}
{% endfor %}
{% endmacro %}
{% macro preload(delta) %}
    {{ move('LR8', delta) }} LD.MULT R0 LR8 {{ cr.tiles }} ;
{% endmacro %}
{% macro chunk(first, count, mask) %}
{% if pieces == 3 %}
    {{ transpose(count, cr.tail ~ '.H') }}
    INC LR6 1 ; ACTIVATE.QUANTIZE identity {{ mask }} {{ cr.tail }}.H {{ cr.tiles }} LR6 ;
    {{ preload(-T - count + 1) }} ;;
{% endif %}
    {{ transpose(count, cr.tail ~ '.H') }}
    {% if pieces == 3 %}DEC LR6 1 ;{% endif %} ACTIVATE.QUANTIZE identity {{ mask }} {{ cr.tail }}.H {{ cr.tiles }} LR6 ;
    {{ preload(-T - count + 1) }} ;;
    {{ transpose(count, cr.qf_in0 ~ '.L') }}
    LD.MULT R0 LR6 {{ cr.tiles }} ;;
{% if pieces == 3 %}
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.tail }}.H ; ACC.ADD ; INC LR6 1 ; LD.MULT R0 LR6 {{ cr.tiles }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.tail }}.H ; ACC.ADD ; DEC LR6 1 ; LD.MULT R0 LR13 {{ cr.in1 }} ;;
{% else %}
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.tail }}.H ; ACC.ADD ; LD.MULT R0 LR13 {{ cr.in1 }} ;;
{% endif %}
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ADD LR7 LR13 LR13 ;;
    ADD LR7 LR7 LR13 ;;
    INC LR7 1 ; ACTIVATE.QUANTIZE identity {{ mask }} {{ cr.qf_out0 }}.L {{ cr.sums }} LR7 ;;
    LD.MULT R0 LR7 {{ cr.sums }} ;;
    INC LR7 1 ; MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_out0 }}.L ; ACC.SUB ;
    ACTIVATE.QUANTIZE identity {{ mask }} {{ cr.tail }}.H {{ cr.sums }} LR7 ;;
    LD.MULT R0 LR7 {{ cr.sums }} ;;
    INC LR7 1 ; MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.tail }}.H ; ACC.SUB ;
    ACTIVATE.QUANTIZE identity {{ mask }} {{ cr.tail }}.H {{ cr.sums }} LR7 ;
{% endmacro %}

unpack:
    SET LR2 {{ cr.stride_lo }} ; SET LR3 {{ cr.stride_hi }} ; SET LR13 LR11 ;;
    SET LR9 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
    INC LR14 7 ; INC LR15 3 ; SET LR6 CR0 ;;
    SET LR8 CR0 ;;
    INC LR6 {{ 3 * T }} ; {{ preload((pieces - 1) * T) }} ;;
position:
{% if W == 2 %}
    {{ chunk(0, 16, 'CR15.L') }}
    {{ preload((pieces - 1) * T + 1) }} ;;
    INC LR13 1 ;;
{% endif %}
    {{ chunk((W - 1) * 16, (D - (W - 1) * 128) // 8, cr.tail ~ '.L') }}
    {{ preload((pieces - 1) * T - T + 1) }} BEQ LR9 LR14 group_done ; ADDBI LRD2 1 ;;
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
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.tail }}.H {{ cr.sums }} LR0 ;
    SET LR1 CR0 ; SET LR10 CR1 ; SET LR11 CR0 ;;
    SET LR14 CR0 ; SET LR15 CR0 ; SET LR9 CR0 ;;
    INC LR14 128 ; {{ move('LR15', D) }} NOP ;;
    {{ move('LR9', 4 * out0_d1 * D // 128) }} NOP ;;
// LR10 heads the padded token; LR11 is the packed row's channel offset.
packed:
    ADD LR12 LR11 LR14 ; SET LR2 LR10 ; SET LR3 LR11 ;;
    SUB LR13 LR12 LR15 ; SET LR4 CR0 ; BLT.S LR11 LR14 first_half ;;
    INC LR2 3 ; DEC LR3 128 ; B main_head ;;
first_half:
{% if W == 2 %}
    ADD LR4 LR2 CR1 ;;
    INC LR4 2 ;;
{% endif %}
main_head:
{% macro main_plane(qf, first, caller_id) %}
    LD.MULT R0 LR2 {{ cr.sums }} ;;
    LD.MULT R1 LR4 {{ cr.sums }} ;;
    MULT.VE LR3 CR1 0 LR0 CR15.L {{ qf }} ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }} ; INC LR2 1 ; BEQ LR4 CR0 no_advance_{{ caller_id }} ;;
    INC LR4 1 ;;
no_advance_{{ caller_id }}:
{% endmacro %}
{% for plane in range(3) %}
    {{ main_plane(cr.qf_out0 ~ '.L' if plane == 0 else cr.tail ~ '.H', plane == 0, plane) }}
{% endfor %}
    BLT.S CR0 LR13 spill ;;
    SET LR11 LR12 ; BLT.S LR12 LR15 store_packed ;;
    SET LR11 CR0 ; INC LR10 {{ 3 * W }} ; B store_packed ;;
spill:
    INC LR10 {{ 3 * W }} ; SET LR11 LR13 ;;
    LD.MULT R0 LR0 {{ cr.sums }} ; SET LR2 LR10 ;;
{% for plane in range(3) %}
    LD.MULT R1 LR2 {{ cr.sums }} ;;
    MULT.VE LR13 CR1 0 LR0 CR15.L {{ cr.qf_out0 ~ '.L' if plane == 0 else cr.tail ~ '.H' }} ; ACC.ADD ; INC LR2 1 ;;
{% endfor %}
store_packed:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 LR9 packed ;;
    HALT ;;
