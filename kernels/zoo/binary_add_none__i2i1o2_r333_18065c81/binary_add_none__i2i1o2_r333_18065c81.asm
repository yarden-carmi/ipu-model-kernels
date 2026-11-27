{% set C = out0_d2 %}
{% set A = out0_d0 %}
{% set B = out0_d1 %}
{% set S = A * B %}
{% set W = (C + 127) // 128 %}
{% set P = C // 16 %}
{% set H = (B + 127) // 128 %}
{% macro move(reg, n) %}
    {% if n > 0 %}INC {{ reg }} {{ n }} ;{% elif n < 0 %}DEC {{ reg }} {{ -n }} ;{% endif %}
{% endmacro %}
{% macro pick(qf) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ qf }}.L ; ACC.RESHAPE LRD2 LRD4 4 ;
{% endmacro %}
// Tile four adjacent b values by sixteen c values. Each input row
// supplies four values at once; the same microtile maps both inputs.
group:
    SET LR6 LR15 ; SET LR7 LR13 ; SET LR9 LR12 ;;
    SET LR8 CR0 ;;
tile:
    SET LR3 {{ cr.seq_lo }} ; SET LR5 {{ cr.tile_dest }} ; SET LR2 CR0 ;;
    ADD LR3 LR3 LR3 ;;
    ADD LR3 LR3 LR3 ; INC LR8 1 ;;
    ADDB LRD2 LR10 ;;
    SET LR2 CR0 ;;
{% for p in range(P - 1) %}
    INC LR2 1 ; BEQ LR7 LR2 phase_{{ p }} ;;
{% endfor %}
{% macro phase(p) %}
phase_{{ p }}:
    {% set x = p * 16 %}
    {% set next = (x + 16 * S) % C // 16 %}
    {{ move('LR7', next - p) }} {{ move('LR6', x // 128) }} LD.MULT R0 LR6 {{ cr.in0 }} ;;
    {% for k in range(16) %}
        {% set z = x + k * S %}
        {% set old = x + (k - 1) * S %}
        {% set row = z // C * W + z % C // 128 %}
        {% set following = (z + S) // C * W + ((z + S) % C // 128 if k < 15 else 0) %}
        {% set delta = z % C % 128 - (old % C % 128 if k else 0) %}
        {{ pick(cr.qf_in0) }} {% if delta %}ADDBI LRD2 {{ delta }} ;{% endif %}
        {% if k %}ADDBI LRD4 1 ;{% endif %} {{ move('LR6', following - row) }}
        {% if k < 15 %}LD.MULT R0 LR6 {{ cr.in0 }} ;{% else %}B stash ;{% endif %} ;;
    {% endfor %}
{% endmacro %}
{{ phase(P - 1) }}
{% for p in range(P - 1) %}{{ phase(p) }}{% endfor %}
stash:
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.H {{ cr.qf_in0 }}.L {{ cr.tiles }} LR0 ;
    LD.MULT R0 LR9 {{ cr.in1 }} ; SET LR5 {{ cr.tile_dest }} ; SET LR2 LR11 ; SET LR3 {{ cr.seq_lo }} ;;
    INC.MODP2 LR2 LR0 7 ;;
{% macro pick_in1(k) %}
    {{ pick(cr.qf_in1) }} INC LR9 {{ H }} ;
    {% if k == 0 %}ADDB LRD2 LR2 ;{% endif %}
    {% if k %}ADDBI LRD4 1 ;{% endif %}
    {% if k < 15 %}LD.MULT R0 LR9 {{ cr.in1 }} ;{% else %}LD.MULT R0 LR0 {{ cr.tiles }} ;{% endif %} ;;
{% endmacro %}
{% for k in range(16) %}{{ pick_in1(k) }}{% endfor %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.H {{ cr.scratch_format }}.H {{ cr.tiles }} LR8 ; BLT.S LR8 LR14 tile ;;
    SET LR7 CR0 ; DEC LR1 1 ; BLT.S LR11 {{ cr.limits }}.L emit_b ;;
    SET LR12 LR9 ;;
    {% if H > 1 %}DEC LR12 {{ H - 1 }} ;;{% endif %}
emit_b:
    SET LR8 CR1 ; SET LR6 CR0 ; INC LR1 1 ;;
    INC LR6 48 ;;
emit_row:
{% macro emit_chunk(count, mask, final) %}
    SET LR4 {{ cr.seq_lo }} ; SET LR5 {{ cr.seq_hi }} ;;
    LD.MULT R0 LR8 {{ cr.tiles }} ; SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ;;
    {% for t in range(count) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.scratch_format }}.H ; ACC.RESHAPE LRD2 LRD4 0 ;
    {% if t == 0 %}ADDB LRD2 LR7 ;{% else %}ADDBI LRD2 -8 ; ADDBI LRD4 8 ;{% endif %} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.scratch_format }}.H ; ACC.RESHAPE LRD2 LRD4 0 ;
    ADDBI LRD2 8 ; ADDBI LRD4 8 ; {% if t + 1 < count or not final %}INC LR8 1 ;{% endif %}
    {% if t + 1 < count %}LD.MULT R0 LR8 {{ cr.tiles }} ;{% else %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
    {% if final %}INC LR7 16 ; BLT.S LR7 LR6 emit_b ;{% endif %}{% endif %} ;;
    {% endfor %}
{% endmacro %}
{% for chunk in range(W) %}
    {{ emit_chunk(8 if chunk + 1 < W else (P - 1) % 8 + 1, 'CR15.L' if chunk + 1 < W else cr.tail ~ '.L', chunk + 1 == W) }}
    {% if chunk + 1 < W %}INC LR1 1 ;;{% endif %}
{% endfor %}
    INC LR1 1 ;;
    BGE.S LR11 {{ cr.limits }}.L next_a ;;
    INC LR11 4 ; INC LR13 1 ;;
    SET LR6 CR0 ;;
    INC LR6 {{ P }} ;;
    SET LR2 LR11 ; BLT.S LR13 LR6 group_block ;;
    SET LR13 CR0 ; INC LR15 {{ W }} ;;
group_block:
    INC.MODP2 LR2 LR0 7 ;;
    BNE LR2 CR0 group ;;
    INC LR12 1 ; B group ;;
next_a:
    SET LR15 CR0 ; SET LR11 CR0 ; SET LR13 CR0 ;;
    INC LR10 1 ; BLT.S LR10 {{ cr.limits }}.H group ;;
    HALT ;;
