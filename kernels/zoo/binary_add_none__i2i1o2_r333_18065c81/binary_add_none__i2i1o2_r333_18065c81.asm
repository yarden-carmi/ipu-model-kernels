{% set C = out0_d2 %}
{% set S = 4 * out0_d1 %}
{% set W = (C + 127) // 128 %}
{% set P = C // 16 %}
{% set H = (out0_d1 + 127) // 128 %}
{% set compensate = C % 128 == 16 and W == 2 %}
{% macro shift(reg, delta) %}
    {% if delta > 0 %}INC {{ reg }} {{ delta }} ;{% elif delta < 0 %}DEC {{ reg }} {{ -delta }} ;{% endif %}
{% endmacro %}
{% macro pick(qf, mask=0) %}
    MULT.VE LR15 CR1 0 LR0 CR15.L {{ qf }}.L ; ACC.RESHAPE LRD2 LRD4 {{ mask }} ;
{% endmacro %}
group:
    SET LR6 LR14 ; SET LR7 LR13 ; SET LR9 LR12 ;;
    SET LR8 CR0 ;;
tile:
    SET LR4 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ; SET LR2 {{ cr.seq_lo }} ;;
    ADD LR4 LR4 LR4 ; ADD LR3 LR3 LR3 ; ADD LR2 LR2 LR2 ;;
    ADD LR4 LR4 LR4 ; ADD LR3 LR3 LR3 ; ADD LR2 LR2 LR2 ;;
    ADD LR4 LR4 LR4 ;;
    ADD LR4 LR4 LR4 ;;
    ADD LR5 LR4 {{ cr.dest_gap }} ; SET LR15 CR1 ; BEQ LR7 CR0 phase_0 ;;
{% for p in range(1, P - 1) %}
    BEQ LR7 LR15 phase_{{ p }} ; INC LR15 1 ;;
{% endfor %}
{% macro phase(p) %}
phase_{{ p }}:
    SET LR15 LR10 ; {{ shift('LR7', (p + S) % P - p) }}
    {{ shift('LR6', p // 8) }} LD.MULT R0 LR6 {{ cr.in0 }} ;;
    {% set prev = namespace(lane=0) %}
    {% for k in range(16) %}
        {% set z = 16 * p + k * S %}
        {% set row = z // C * W + z % C // 128 %}
        {% set lane = z % C % 128 %}
        {% set zr = z + 16 %}
        {% set rr = zr // C * W + zr % C // 128 %}
        {% set next = z + S %}
        {% set nr = next // C * W + (next % C // 128 if k < 15 else 0) %}
        {% if rr != row %}
            {% if k %}ADDBI LRD4 1 ;;{% endif %}
            {{ pick(cr.qf_in0, 4) }} {{ shift('LR15', lane - 16 - prev.lane) }}
            SET LR5 LR4 ; INC LR6 {{ rr - row }} ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
            {% set lane = zr % C % 128 - 16 %}
            {{ pick(cr.qf_in0, 4) }} {{ shift('LR15', lane - (z % C % 128 - 16)) }}
            ADD LR5 LR4 {{ cr.dest_gap }} ; {{ shift('LR6', nr - rr) }}
        {% else %}
            {{ pick(cr.qf_in0) }} {{ shift('LR15', lane - prev.lane) }}
            {% if k %}ADDBI LRD4 1 ;{% endif %} {{ shift('LR6', nr - row) }}
        {% endif %}
        {% if k < 15 %}LD.MULT R0 LR6 {{ cr.in0 }} ;{% else %}B stash ;{% endif %} ;;
        {% set prev.lane = lane %}
    {% endfor %}
{% endmacro %}
{{ phase(P - 1) }}
{% for p in range(P - 1) %}{{ phase(p) }}{% endfor %}
stash:
{% if compensate %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.tiles }} LR0 ; SET LR15 CR1 ;;
    LD.MULT R0 LR0 {{ cr.tiles }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.scratch_format }}.H {{ cr.tiles }} LR15 ;
    ADDBI LRD4 -15 ; SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ; LD.MULT R0 LR9 {{ cr.in1 }} ;;
{% else %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.tiles }} LR0 ;
    LD.MULT R0 LR9 {{ cr.in1 }} ; ADDBI LRD4 -15 ; SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ;;
{% endif %}
    SET LR15 LR11 ;;
    INC.MODP2 LR15 LR0 7 ;;
{% for k in range(16) %}
    {{ pick(cr.qf_in1) }} INC LR9 {{ H }} ; {% if k %}ADDBI LRD4 1 ;{% endif %}
    {% if k < 15 %}LD.MULT R0 LR9 {{ cr.in1 }} ;{% else %}LD.MULT R0 LR0 {{ cr.tiles }} ;{% endif %} ;;
{% endfor %}
{% if compensate %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR15 CR1 ; LD.MULT R0 LR15 {{ cr.tiles }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.scratch_format }}.H ; ACC.ADD ; ADD LR15 LR8 CR1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.tiles }} LR15 ; INC LR15 1 ;;
    LD.MULT R0 LR15 {{ cr.tiles }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB ; INC LR15 {{ P }} ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.scratch_format }}.H {{ cr.tiles }} LR15 ;
    INC LR8 1 ; BLT.S LR8 {{ cr.limits }}.H tile ;;
{% else %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.scratch_format }}.L {{ cr.tiles }} LR8 ;
    INC LR8 1 ; BLT.S LR8 {{ cr.limits }}.H tile ;;
{% endif %}
    SET LR7 CR0 ; SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ;;
    SET LR6 CR0 ;;
    INC LR6 112 ;;
emit:
    SET LR8 CR1 ; SET LR15 LR7 ;;
    {% if compensate %}INC LR8 1 ;;{% endif %}
{% macro emit_chunk(count, mask, qf, part='direct') %}
    SET LR4 LR2 ; SET LR5 LR3 ; LD.MULT R0 LR8 {{ cr.tiles }} ;;
    {% for t in range(count) %}
        MULT.VE LR15 CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0 ; {% if t %}DEC LR15 8 ; ADDBI LRD4 8 ;{% endif %} ;;
        MULT.VE LR15 CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0 ; INC LR15 8 ; ADDBI LRD4 8 ; INC LR8 1 ;
        {% if t + 1 < count %}LD.MULT R0 LR8 {{ cr.tiles }} ;
        {% elif part == 'main' %}ACTIVATE.QUANTIZE identity {{ mask }} {{ qf }} {{ cr.tiles }} LR0 ;
        {% elif part == 'residual' %}LD.MULT R0 LR0 {{ cr.tiles }} ;
        {% else %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;{% endif %} ;;
    {% endfor %}
    {% if part == 'main' %}
        {{ shift('LR8', P - count) }} SET LR15 LR7 ;;
    {% elif part == 'residual' %}
        MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD ;
        ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
        INC LR1 1 ;;
    {% else %}INC LR1 1 ;;{% endif %}
{% endmacro %}
{% if compensate %}
    {{ emit_chunk(8, 'CR15.L', cr.qf_out0 ~ '.L', 'main') }}
    {{ emit_chunk(8, 'CR15.L', cr.scratch_format ~ '.H', 'residual') }}
    DEC LR8 {{ P }} ; SET LR15 LR7 ;;
    {{ emit_chunk(1, cr.tail ~ '.L', cr.qf_out0 ~ '.L', 'main') }}
    {{ emit_chunk(1, cr.tail ~ '.L', cr.scratch_format ~ '.H', 'residual') }}
{% else %}
    {% if W == 2 %}
        {{ emit_chunk(8, 'CR15.L', cr.scratch_format ~ '.L') }}
        SET LR15 LR7 ;;
    {% endif %}
    {{ emit_chunk((P - 1) % 8 + 1, cr.tail ~ '.L', cr.scratch_format ~ '.L') }}
{% endif %}
    INC LR7 16 ; BLT.S LR7 LR6 emit ;;
    BGE.S LR11 {{ cr.limits }}.L next_batch ;;
    INC LR11 8 ; INC LR13 2 ;;
    BLT.S {{ cr.limits }}.H LR13 wrap_group ;;
next_group:
    SET LR15 LR11 ;;
    INC.MODP2 LR15 LR0 7 ;;
    BNE LR15 CR0 group ;;
    INC LR12 1 ; B group ;;
wrap_group:
    SUB LR13 LR13 {{ cr.limits }}.H ; INC LR14 {{ W }} ;;
    DEC LR13 1 ; B next_group ;;
next_batch:
    SET LR6 CR0 ;;
    INC LR6 3 ;;
    BGE.S LR10 LR6 finish ;;
    SET LR14 CR0 ; SET LR13 CR0 ; SET LR11 CR0 ;;
    SET LR12 LR9 ; INC LR10 1 ;;
    {% if H > 1 %}DEC LR12 {{ H - 1 }} ;{% endif %} B group ;;
finish:
    HALT ;;
