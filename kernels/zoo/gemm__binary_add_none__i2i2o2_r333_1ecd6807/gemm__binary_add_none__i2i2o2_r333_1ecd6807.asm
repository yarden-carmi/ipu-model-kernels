{% macro mac() -%}
MULT.RC.VE LR0 LR9 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD
{%- endmacro %}
{% macro weight() -%}
LD.MULT.CYCLIC LR3 {{cr.w}} LR0 ; INC LR3 1
{%- endmacro %}
{% macro integer(reg, value) %}
    SET {{reg}} CR0 ;;
    {% for shift in [24,16,8,0] %}
        {% if value // (2 ** (shift+8)) %}
            {% for bit in range(8) %}
    ADD {{reg}} {{reg}} {{reg}} ;;
            {% endfor %}
        {% endif %}
        {% if (value // (2 ** shift)) % 256 %}
    INC {{reg}} {{(value // (2 ** shift)) % 256}} ;;
        {% endif %}
    {% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ; SET LR5 {{cr.s0_n}} ;;
    SET LR14 CR0 ; SET LR15 CR0 ;;
    DEC LR4 1 ; INC LR12 128 ;;
    {{ integer('LR13', in0_d1) }}
period_start:
    SET LR2 CR0 ; SET LR3 CR0 ;;
    DEC LR3 1 ;;
physical_row:
    LD.MULT R0 LR3 {{cr.w}} ; INC LR3 1 ; SET LR6 LR12 ;;
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ;;
segment:
    SET LR7 LR4 ; SET LR8 {{cr.chunks}} ;;
chunk:
    LD.MULT R0 LR7 {{cr.in0}} ; INC LR7 1 ; DEC LR8 1 ; SET LR10 CR0 ;;
    INC LR10 125 ; BNE LR8 CR0 endpoints ;;
    SET LR10 {{cr.end}} ;;
endpoints:
    SUB LR9 LR0 CR1 ; {{weight()}} ;;
    BLT.S LR10 LR9 final_lane ;;
lane:
    {{mac()}} ; INC LR9 1 ; {{weight()}} ; BLT.S LR9 LR10 lane ;;
final_lane:
    {{mac()}} ; INC LR9 1 ; BNE LR8 CR0 chunk ;;
    # Residual view address is b + B*p + M*c in packed storage.
    SUB LR7 LR12 LR6 ; SET LR8 LR6 ;;
    BLT.S LR6 LR5 gather_init ;;
    SET LR8 LR5 ;;
gather_init:
    SUB LR6 LR6 LR8 ; SUB LR5 LR5 LR8 ; DEC LR7 1 ;;
    {{ integer('LR9', s0_m % 128) }}
    {{ integer('LR10', s0_m // 128) }}
gather:
    LD.MULT R0 LR14 {{cr.in1}} ; DEC LR8 1 ;;
    MULT.EE LR15 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; AGG.SUM LR7 {{cr.full}}.H ; INC LR7 1 ;;
    ADD LR14 LR14 LR10 ; ADD LR15 LR15 LR9 ;;
    BLT.S LR15 LR12 no_carry ;;
    INC LR14 1 ; SUB LR15 LR15 LR12 ;;
no_carry:
    BNE LR8 CR0 gather ;;
    BNE LR5 CR0 store ;;
    ADD LR4 LR4 {{cr.chunks}} ; SET LR5 {{cr.s0_n}} ; DEC LR13 1 ;;
    BEQ LR13 CR0 next_batch ;;
    {{ integer('LR9', in0_d0) }}
    ADD LR11 LR11 LR9 ; B residual_base ;;
next_batch:
    {{ integer('LR9', s0_m - in0_d0 - 1) }}
    SUB LR11 LR11 LR9 ;;
    {{ integer('LR13', in0_d1) }}
residual_base:
    SET LR14 CR0 ; SET LR15 LR11 ;;
normalize:
    BLT.S LR15 LR12 segment_end ;;
    INC LR14 1 ; SUB LR15 LR15 LR12 ; B normalize ;;
segment_end:
    BNE LR6 CR0 segment ;;
store:
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR1 ; INC LR2 1 ;;
    INC LR1 1 ;;
    BEQ LR1 {{cr.rows}} done ;;
    BNE LR2 {{cr.period}} physical_row ;;
    B period_start ;;
done:
    HALT ;;
