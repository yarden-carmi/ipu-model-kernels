{% set C = in0_d2 %}
{% set S = in0_d0 * in0_d1 %}
{% set W = (C + 127) // 128 %}
{% set P = C // 16 %}
{% set H = (S + 127) // 128 %}
{% set tile = namespace(size=8) %}
{% for n in [16, 32, 64, 128] %}
    {% if C % n == 0 and S % n == 0 %}{% set tile.size = n %}{% endif %}
{% endfor %}
{% set T = tile.size %}
{% macro shift(reg, delta) %}
    {% if delta > 0 %}INC {{ reg }} {{ delta }} ;{% elif delta < 0 %}DEC {{ reg }} {{ -delta }} ;{% endif %}
{% endmacro %}
{% macro seq() %}
    SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ;
{% endmacro %}
{% macro reset_dest() %}
    SET LR4 {{ cr.seq_lo }} ; SET LR5 {{ cr.seq_hi }} ;
{% endmacro %}
{% macro pick(lane, qf) %}
    MULT.VE {{ lane }} CR1 0 LR0 CR15.L {{ qf }} ; ACC.RESHAPE LRD2 LRD4 0 ;
{% endmacro %}

// One group covers eight consecutive storage offsets of the strided view.
// The temporary tiles have 16 positions by 8 offsets, position-major.
group:
    SET LR6 LR10 ; SET LR7 LR11 ; SET LR8 LR11 ;;
    SET LR9 LR13 ; SET LR14 CR0 ;;
    INC LR14 1 ;;
    SET LR15 CR0 ;;
    INC LR15 128 ;;
    BLT.S LR7 LR15 gather ;;
    DEC LR7 128 ; INC LR6 1 ;;
gather:
    {{ seq() }} LD.MULT R0 LR6 {{ cr.in0 }} ;;
    {{ reset_dest() }} SET LR15 CR0 ;;
    {% if C > T %}INC LR15 {{ T }} ;;{% endif %}
    {% for p in range(C // T - 1) %}
        INC LR15 {{ T }} ; BLT.S LR8 LR15 gather_{{ p }} ;;
    {% endfor %}
{% macro gather_phase(p) %}
gather_{{ p }}:
    {% for i in range(16) %}
        {% set z = p * T + i * S %}
        {% set next = z + S %}
        {% set row = z // C * W + z % C // 128 %}
        {% set nr = next // C * W + next % C // 128 %}
        {{ pick('LR7', cr.qf_in0 ~ '.L') }}
        {{ shift('LR6', nr - row) }}
        {% if i %}{{ shift('LR7', z % C % 128 - (z-S) % C % 128) }} ADDBI LRD4 8 ;{% endif %}
        {% if i < 15 %}
            LD.MULT R0 LR6 {{ cr.in0 }} ;;
        {% else %}
            ACTIVATE.QUANTIZE identity CR15.L {{ cr.scratch_format }}.L {{ cr.tiles }} LR0 ;;
            LD.MULT R0 LR0 {{ cr.tiles }} ; {{ shift('LR8', next % C - p*T) }} {{ shift('LR7', next % C % 128 - z % C % 128) }} B gather_rhs ;;
        {% endif %}
    {% endfor %}
{% endmacro %}
{{ gather_phase(C // T - 1) }}
{% for p in range(C // T - 1) %}{{ gather_phase(p) }}{% endfor %}

gather_rhs:
    // Splitting scratch values into a main part and a residual avoids
    // losing small values when different input row scales share a tile.
    SET LR15 CR0 ;;
    INC LR15 {{ 2*P + 1 }} ;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.scratch_format }}.L ; ACC.SUB ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.scratch_format }}.H {{ cr.tiles }} LR15 ;
    LD.MULT R0 LR9 {{ cr.in1 }} ;;
    {{ reset_dest() }} ;;
    {% for i in range(16) %}
        {{ pick('LR12', cr.qf_in1 ~ '.L') }}
        {% if i %}ADDBI LRD4 8 ;{% endif %}
        {% if i < 15 %}
            LD.MULT R0 LR9 {{ cr.in1 }} ; INC LR9 {{ H }} ;;
        {% else %}
            LD.MULT R0 LR0 {{ cr.tiles }} ; INC LR9 {{ H }} ;;
        {% endif %}
    {% endfor %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.scratch_format }}.L ; ACC.ADD ; LD.MULT R0 LR15 {{ cr.tiles }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.scratch_format }}.H ; ACC.ADD ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.scratch_format }}.L {{ cr.tiles }} LR14 ;
    ;;
    LD.MULT R0 LR14 {{ cr.tiles }} ; ADD LR15 LR14 CR1 ;;
    INC LR15 {{ P - 1 }} ;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.scratch_format }}.L ; ACC.SUB ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.scratch_format }}.H {{ cr.tiles }} LR15 ;;
    INC LR14 1 ; BLT.S LR14 {{ cr.tail }}.H gather ;;

    SET LR2 {{ cr.stride_seq_lo }} ; SET LR3 {{ cr.stride_seq_hi }} ; SET LR7 CR0 ;;
    SET LR6 LR1 ; SET LR8 CR0 ;;
    INC LR8 4 ; SET LR14 CR0 ;;
    INC LR14 8 ;;
emit:
    SET LR9 CR1 ; SET LR15 LR7 ;;
{% macro emit_part(count, mask, residual) %}
    {% set qf = cr.scratch_format ~ ('.H' if residual else '.L') %}
    {{ reset_dest() }} LD.MULT R0 LR9 {{ cr.tiles }} ;;
    {% for i in range(count) %}
        {{ pick('LR15', qf) }} {% if i %}ADDBI LRD4 8 ; DEC LR15 64 ;{% endif %} ;;
        {{ pick('LR15', qf) }} INC LR15 64 ; ADDBI LRD4 8 ;
        {% if i + 1 < count %}
            LD.MULT R0 LR9 {{ cr.tiles }} ; INC LR9 1 ;;
        {% elif not residual %}
            LD.MULT R0 LR0 {{ cr.tiles }} ;;
        {% else %}
            ACTIVATE.QUANTIZE identity {{ mask }} {{ cr.scratch_format }}.H {{ cr.tiles }} LR0 ;;
        {% endif %}
    {% endfor %}
{% endmacro %}
{% macro emit_chunk(count, mask) %}
    INC LR9 {{ P }} ;;
    {{ emit_part(count, mask, true) }}
    DEC LR9 {{ P + count - 1 }} ; SET LR15 LR7 ;;
    {{ emit_part(count, mask, false) }}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.scratch_format }}.H ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; INC LR9 1 ; SET LR15 LR7 ;;
{% endmacro %}
{% if W == 2 %}{{ emit_chunk(8, 'CR15.L') }}{% endif %}
{{ emit_chunk((P - 1) % 8 + 1, cr.tail ~ '.L') }}
    INC LR7 1 ;;
    {% for i in range(((out0_d1 - 1) * W + 254) // 255) %}
        INC LR6 {{ [255, (out0_d1 - 1) * W - 255*i] | min }} ;;
    {% endfor %}
    BEQ LR7 LR14 group_done ;;
    BNE LR7 LR8 emit ;;
    SET LR6 LR1 ;;
    INC LR6 {{ W }} ; B emit ;;
group_done:
    INC LR1 {{ 2 * W }} ; INC LR11 8 ; INC LR12 8 ;;
    SET LR7 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    INC LR8 {{ [C, 128] | min }} ; INC LR9 128 ;;
    {% if C > 128 %}INC LR8 {{ C - 128 }} ;;{% endif %}
    {% for i in range((out0_d1 * W + 254) // 255) %}
        INC LR7 {{ [255, out0_d1 * W - 255*i] | min }} ;;
    {% endfor %}
    BEQ LR1 LR7 finish ;;
    BLT.S LR11 LR8 group_col_ready ;;
    SET LR11 CR0 ; INC LR10 {{ W }} ;;
group_col_ready:
    BLT.S LR12 LR9 group ;;
    SET LR12 CR0 ; INC LR13 1 ; B group ;;
finish:
    HALT ;;
