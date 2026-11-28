{% set C = out0_d2 %}
{% set S = 4 * out0_d1 %}
{% set W = (C + 127) // 128 %}
{% set P = C // 16 %}
{% set H = (out0_d1 + 127) // 128 %}
{% set compensate = C % 128 == 16 and W == 2 %}
// The 16-lane tail uses main and residual scratch rows to preserve small
// values when the transpose mixes elements from differently scaled rows.
// In that path, tile lane 32*(token/2) + 2*channel + token%2 lets
// ACC.STRIDE extract a token's 16 channels in one word.
{% macro shift(reg, delta) %}
    {% if delta > 0 %}INC {{ reg }} {{ delta }} ;{% elif delta < 0 %}DEC {{ reg }} {{ -delta }} ;{% endif %}
{% endmacro %}
{% macro pick(qf, mask=0) %}
    MULT.VE LR15 CR1 0 LR0 CR15.L {{ qf }}.L ; ACC.RESHAPE LRD2 LRD4 {{ mask }} ;
{% endmacro %}
{% if compensate %}
    DEC LR1 1 ;;
{% endif %}
{% set prefix %}
group:
    SET LR6 LR14 ; SET LR7 LR13 ; SET LR9 LR12 ;;
    SET LR8 {{ 'CR1' if compensate else 'CR0' }} ;;
tile:
{% if compensate %}
    SET LR4 {{ cr.limits }} ; SET LR3 {{ cr.seq_hi }} ; SET LR2 {{ cr.seq_lo }} ;;
    ADD LR5 LR4 {{ cr.dest_gap }} ; ADD LR3 LR3 LR3 ; ADD LR2 LR2 LR2 ;;
    SET LR15 CR1 ; ADD LR3 LR3 LR3 ; ADD LR2 LR2 LR2 ; B dispatch ;;
resume:
    BR LR7 ;;
dispatch:
    BEQ LR7 CR0 phase_0 ;;
{% else %}
    SET LR4 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ; SET LR2 {{ cr.seq_lo }} ;;
    ADD LR4 LR4 LR4 ; ADD LR3 LR3 LR3 ; ADD LR2 LR2 LR2 ;;
    ADD LR4 LR4 LR4 ; ADD LR3 LR3 LR3 ; ADD LR2 LR2 LR2 ;;
    ADD LR4 LR4 LR4 ;;
    ADD LR4 LR4 LR4 ;;
    ADD LR5 LR4 {{ cr.dest_gap }} ; SET LR15 CR1 ; BEQ LR7 CR0 phase_0 ;;
{% endif %}
{% for p in range(1, P - 1) %}
    BEQ LR7 LR15 phase_{{ p }} ; INC LR15 1 ;;
{% endfor %}
{% endset %}
{{ prefix }}
{% macro phase(p, target=0) %}
phase_{{ p }}:
    SET LR15 LR10 ; {% if compensate %}SET LR7 CR0 ;{% else %}{{ shift('LR7', (p + S) % P - p) }}{% endif %}
    {{ shift('LR6', p // 8) }} LD.MULT R0 LR6 {{ cr.in0 }} ;;
    {% set prev = namespace(lane=0) %}
    {% for k in range(16) %}
        {% set advance = ('INC LR7 ' ~ target ~ ' ;') if compensate and k == 0 and target else '' %}
        {% set z = 16 * p + k * S %}
        {% set row = z // C * W + z % C // 128 %}
        {% set lane = z % C % 128 %}
        {% set zr = z + 16 %}
        {% set rr = zr // C * W + zr % C // 128 %}
        {% set next = z + S %}
        {% set nr = next // C * W + (next % C // 128 if k < 15 else 0) %}
        {% if rr != row %}
            {% if compensate and k == 0 %}INC LR7 {{ target }} ;;{% endif %}
             {% if k %}ADDBI LRD4 1 ;;{% endif %}
            {{ pick(cr.qf_in0, 4) }} {{ shift('LR15', lane - 16 - prev.lane) }}
            SET LR5 LR4 ; INC LR6 {{ rr - row }} ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
            {% set lane = zr % C % 128 - 16 %}
            {{ pick(cr.qf_in0, 4) }} {{ shift('LR15', lane - (z % C % 128 - 16)) }}
            ADD LR5 LR4 {{ cr.dest_gap }} ; {{ shift('LR6', nr - rr) }}
        {% else %}
            {{ pick(cr.qf_in0) }} {{ shift('LR15', lane - prev.lane) }} {{ advance }}
             {% if k %}ADDBI LRD4 1 ;{% endif %} {{ shift('LR6', nr - row) }}
        {% endif %}
        {% if k < 15 %}LD.MULT R0 LR6 {{ cr.in0 }} ;{% else %}
            {% if compensate %}ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.tiles }} LR0 ;{% endif %}
            B stash ;
        {% endif %} ;;
        {% set prev.lane = lane %}
    {% endfor %}
{% endmacro %}
{# Count bundled words to get phase PCs. The first tile selects its phase
   from the group offset; later tiles jump directly to the next phase. #}
{% set pc = namespace(next=(prefix.split(';;') | length) - 1 + (1 if compensate else 0), table={}) %}
{% for i in range(P) %}
    {% set p = (i + P - 1) % P %}
    {% set pc.table = dict(pc.table, **{('p' ~ p): pc.next}) %}
    {% set pc.next = pc.next + (phase(p).split(';;') | length) - 1 %}
{% endfor %}
{% for i in range(P) %}
    {% set p = (i + P - 1) % P %}
    {{ phase(p, pc.table['p' ~ ((p + S) % P)]) }}
{% endfor %}
stash:
{% if compensate %}
    INC LR8 1 ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.tiles }} LR8 ;;
    LD.MULT R0 LR0 {{ cr.tiles }} ; ADD LR15 LR8 {{ cr.tail }}.H ; SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.scratch_format }}.H {{ cr.tiles }} LR15 ; SET LR4 {{ cr.limits }} ; ADD LR2 LR2 LR2 ; ADD LR3 LR3 LR3 ;;
    ADD LR5 LR4 {{ cr.dest_gap }} ; ADD LR2 LR2 LR2 ; ADD LR3 LR3 LR3 ; BLT.S LR8 {{ cr.tail }}.H resume ;;
{% else %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.scratch_format }}.L {{ cr.tiles }} LR8 ;
    INC LR8 1 ; BLT.S LR8 {{ cr.limits }}.H tile ;;
{% endif %}
    SET LR7 CR0 ; SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ;;
    SET LR6 CR0 ;;
    INC LR6 112 ;;
    {% if compensate %}SET LR8 CR1 ;;{% endif %}
emit_direct:
    {% if compensate %}INC LR8 1 ; SET LR15 LR7 ;;{% else %}SET LR8 CR1 ; SET LR15 LR7 ;;{% endif %}
{% macro direct_chunk(count, mask, qf, part='direct', reset=false, last=false) %}
    SET LR4 LR2 ; SET LR5 LR3 ; LD.MULT R0 LR8 {{ cr.tiles }} ;;
    {% for t in range(count) %}
        MULT.VE LR15 CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0 ; {% if t %}DEC LR15 8 ; ADDBI LRD4 8 ;{% endif %} ;;
        MULT.VE LR15 CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0 ; INC LR15 8 ; ADDBI LRD4 8 ; INC LR8 1 ;
        {% if t + 1 < count %}LD.MULT R0 LR8 {{ cr.tiles }} ;
        {% elif part == 'residual' %}ACTIVATE.QUANTIZE identity {{ mask }} {{ cr.scratch_format }}.H {{ cr.tiles }} LR0 ;
        {% elif part == 'main' %}LD.MULT R0 LR0 {{ cr.tiles }} ;
        {% else %}LD.MULT R0 LR1 {{ cr.in1 }} ;{% endif %} ;;
    {% endfor %}
    {% if part == 'residual' %}
        DEC LR8 {{ P + 1 + count }} ; SET LR15 LR7 ;;
    {% else %}
        {% if part == 'main' %}MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.scratch_format }}.H ; ACC.ADD ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in1 }} ;;{% endif %}
        MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
        ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; {% if reset %}DEC LR8 {{ P + 1 }} ; SET LR15 LR7 ;{% endif %} {% if last and part == 'main' %}SET LR8 CR1 ; INC LR7 16 ; BLT.S LR7 LR6 emit_direct ;{% endif %} ;;
        {% if part != 'main' %}INC LR1 1 ; {% if last %}INC LR7 16 ; BLT.S LR7 LR6 emit_direct ;{% endif %} ;;{% endif %}
    {% endif %}
{% endmacro %}
{% if compensate %}
    INC LR8 {{ P + 1 }} ;;
    {{ direct_chunk(8, 'CR15.L', cr.scratch_format ~ '.H', 'residual') }}
    {{ direct_chunk(8, 'CR15.L', cr.qf_in0 ~ '.L', 'main') }}
    INC LR8 {{ P + 1 }} ; SET LR15 LR7 ;;
    {{ direct_chunk(1, cr.tail ~ '.L', cr.scratch_format ~ '.H', 'residual') }}
    {{ direct_chunk(1, cr.tail ~ '.L', cr.qf_in0 ~ '.L', 'main', last=true) }}
{% else %}
    {% if W == 2 %}
        {{ direct_chunk(8, 'CR15.L', cr.scratch_format ~ '.L') }}
        SET LR15 LR7 ;;
    {% endif %}
    {{ direct_chunk((P - 1) % 8 + 1, cr.tail ~ '.L', cr.scratch_format ~ '.L', last=true) }}
{% endif %}
{% if false %}
{% if compensate %}
    LD.MULT R0 LR0 {{ cr.tiles }} ; SET LR2 CR1 ; SET LR3 {{ cr.seq_hi }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.scratch_format }}.H {{ cr.tiles }} LR2 ;
    ADDBI LRD4 -30 ; SET LR15 LR11 ; LD.MULT R0 LR9 {{ cr.in1 }} ;;
{% else %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.tiles }} LR0 ;
    LD.MULT R0 LR9 {{ cr.in1 }} ; ADDBI LRD4 -15 ; SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ;;
    SET LR15 LR11 ;;
{% endif %}
    INC.MODP2 LR15 LR0 7 ; {% if compensate %}SET LR2 {{ cr.seq_lo }} ;{% endif %} ;;
{% for k in range(16) %}
    {{ pick(cr.qf_in1) }} INC LR9 {{ H }} ; {% if k %}ADDBI LRD4 {{ 2 if compensate else 1 }} ;{% endif %}
    {% if k < 15 %}LD.MULT R0 LR9 {{ cr.in1 }} ;{% else %}LD.MULT R0 LR0 {{ cr.tiles }} ;{% endif %} ;;
{% endfor %}
{% if compensate %}
    // Set up the next gather's reshape indices while storing this tile.
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR15 {{ cr.tiles }} ; SET LR15 CR1 ; SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.scratch_format }}.H ; ACC.ADD ; INC LR8 1 ; ADD LR2 LR2 LR2 ; ADD LR3 LR3 LR3 ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.tiles }} LR8 ;;
    LD.MULT R0 LR8 {{ cr.tiles }} ; SET LR4 {{ cr.limits }} ; ADD LR2 LR2 LR2 ; ADD LR3 LR3 LR3 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB ; ADD LR15 LR8 {{ cr.tail }}.H ; ADD LR5 LR4 {{ cr.dest_gap }} ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.scratch_format }}.H {{ cr.tiles }} LR15 ;
    BLT.S LR8 {{ cr.tail }}.H resume ;;
{% else %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.scratch_format }}.L {{ cr.tiles }} LR8 ;
    INC LR8 1 ; BLT.S LR8 {{ cr.limits }}.H tile ;;
{% endif %}
{% if compensate %}
    // Preload the first main tile; the residual bank has a separate cursor.
    SET LR7 CR0 ; SET LR6 {{ cr.tail }}.H ; SET LR9 CR0 ;;
     INC LR6 2 ; SET LR8 CR1 ; SET LR2 {{ cr.seq_lo }} ;;
     SET LR3 {{ cr.seq_hi }} ;;
     INC LR8 1 ; ADD LR2 LR2 LR2 ; ADD LR3 LR3 LR3 ; LD.MULT R0 LR8 {{ cr.tiles }} ;;
{% else %}
    SET LR7 CR0 ; SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ;;
    SET LR6 CR0 ;;
    INC LR6 112 ;;
{% endif %}
{% macro emit_chunk(count, mask, qf) %}
    SET LR4 LR2 ; SET LR5 LR3 ; LD.MULT R0 LR8 {{ cr.tiles }} ;;
    {% for t in range(count) %}
        MULT.VE LR15 CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0 ; {% if t %}DEC LR15 8 ; ADDBI LRD4 8 ;{% endif %} ;;
        MULT.VE LR15 CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0 ; INC LR15 8 ; ADDBI LRD4 8 ; INC LR8 1 ;
        {% if t + 1 < count %}LD.MULT R0 LR8 {{ cr.tiles }} ;
        {% else %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;{% endif %} ;;
    {% endfor %}
    INC LR1 1 ;;
{% endmacro %}
{# Stride installs the first 16 channels of each 32-lane segment.
   The following two scatters replace the unwanted upper 16 lanes. #}
{% macro pipeline_emit(ptr, qf, nextptr, store=false) %}
    {% for t in range(4) %}
        MULT.VE LR7 CR1 0 LR0 CR15.L {{ qf }} ; ACC.STRIDE 64 on on LR9 ;
        INC {{ ptr }} 1 ; LD.MULT R0 {{ ptr }} {{ cr.tiles }} ;
        {% if t == 0 %}SET LR4 {{ cr.seq_lo }} ; SET LR5 {{ cr.seq_hi }} ;{% endif %} ;;
        MULT.VE LR7 CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0 ; ADDBI LRD4 {{ 16 if t == 0 else 24 }} ; SET LR15 LR7 ; {% if t < 3 %}INC {{ ptr }} 1 ;{% endif %} ;;
        MULT.VE LR15 CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0 ; ADDBI LRD4 8 ; INC LR15 16 ; INC LR9 1 ;
        LD.MULT R0 {{ ptr if t < 3 else nextptr }} {{ cr.tiles }} ;
        {% if t == 3 and store %}ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.tiles }} LR0 ;{% endif %} ;;
    {% endfor %}
{% endmacro %}
{% macro emit_token(step, last=false) %}
    {{ pipeline_emit('LR8', cr.qf_out0 ~ '.L', 'LR6', true) }}
    {{ pipeline_emit('LR6', cr.scratch_format ~ '.H', 'LR0') }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD ; INC LR1 1 ; INC LR8 1 ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; LD.MULT R0 LR8 {{ cr.tiles }} ;;
    MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.STRIDE 64 on on LR0 ; SET LR8 CR1 ; INC LR6 1 ; SET LR15 CR0 ;
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.tiles }} LR0 ; LD.MULT R0 LR6 {{ cr.tiles }} ;;
    MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.scratch_format }}.H ; ACC.STRIDE 64 on on LR0 ; INC LR8 1 ; LD.MULT R0 LR0 {{ cr.tiles }} ;
    INC LR15 97 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
    ADD LR6 LR8 {{ cr.tail }}.H ; INC LR7 {{ step }} ; INC LR1 1 ; LD.MULT R0 LR8 {{ cr.tiles }} ;
    {% if last %}BLT.S LR7 LR15 emit ;{% endif %} ;;
{% endmacro %}
emit:
{% if compensate %}
     {{ emit_token(1) }}
     {{ emit_token(31, true) }}
{% else %}
    SET LR8 CR1 ; SET LR15 LR7 ;;
    {% if W == 2 %}
        {{ emit_chunk(8, 'CR15.L', cr.scratch_format ~ '.L') }}
        SET LR15 LR7 ;;
    {% endif %}
    {{ emit_chunk((P - 1) % 8 + 1, cr.tail ~ '.L', cr.scratch_format ~ '.L') }}
    INC LR7 16 ; BLT.S LR7 LR6 emit ;;
{% endif %}
{% if compensate %}
    SET LR6 CR0 ;; INC LR6 {{ out0_d1 - 8 }} ;;
    BGE.S LR11 LR6 next_batch ;;
    SET LR6 CR0 ;; INC LR6 {{ P - 1 }} ;;
{% else %}
    BGE.S LR11 {{ cr.limits }}.L next_batch ;;
{% endif %}
    INC LR11 8 ; INC LR13 2 ;;
    BLT.S {{ 'LR6' if compensate else cr.limits ~ '.H' }} LR13 wrap_group ;;
next_group:
    SET LR15 LR11 ;;
    INC.MODP2 LR15 LR0 7 ;;
    BNE LR15 CR0 group ;;
    INC LR12 1 ; B group ;;
wrap_group:
    SUB LR13 LR13 {{ 'LR6' if compensate else cr.limits ~ '.H' }} ; INC LR14 {{ W }} ;;
    DEC LR13 1 ; B next_group ;;
next_batch:
    SET LR6 CR0 ;;
    INC LR6 3 ;;
    BGE.S LR10 LR6 finish ;;
    SET LR14 CR0 ; SET LR13 CR0 ; SET LR11 CR0 ;;
    {% if compensate %}
        // LR9 was reused for the emit bound. Advance the last group's in1
        // start from this batch's final token block to the next batch base.
        INC LR10 1 ;;
        {% for _ in range((C * H - H + 1) // 128) %}INC LR12 128 ;;
        {% endfor %}
        INC LR12 {{ (C * H - H + 1) % 128 }} ; B group ;;
    {% else %}
        SET LR12 LR9 ; INC LR10 1 ;;
        {% if H > 1 %}DEC LR12 {{ H - 1 }} ;{% endif %} B group ;;
    {% endif %}
{% endif %}
    {% if compensate %}
    SET LR6 CR0 ;; INC LR6 {{ out0_d1 - 8 }} ;;
    BGE.S LR11 LR6 direct_batch ;;
    SET LR6 CR0 ;; INC LR6 {{ P - 1 }} ;;
    {% else %}
    BGE.S LR11 {{ cr.limits }}.L direct_batch ;;
    {% endif %}
    INC LR11 8 ; INC LR13 2 ;;
    BLT.S {{ 'LR6' if compensate else cr.limits ~ '.H' }} LR13 direct_wrap ;;
    B group ;;
direct_wrap:
    SUB LR13 LR13 {{ 'LR6' if compensate else cr.limits ~ '.H' }} ; INC LR14 {{ W }} ;;
    DEC LR13 1 ; B group ;;
direct_batch:
    SET LR6 CR0 ;; INC LR6 3 ;;
    BGE.S LR10 LR6 finish ;;
    SET LR14 CR0 ; SET LR13 CR0 ; SET LR11 CR0 ;;
    INC LR10 1 ; B group ;;
finish:
    HALT ;;
