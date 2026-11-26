{% set chunks = (in0_d2 + 127) // 128 %}
{% set remainder = s0_m % 128 %}
{% set padded = out0_d1 % 64 != 0 %}
{% macro product(index) -%}
MULT.RC.VV {{index}} R0 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR3 {{cr.full}}.L
{%- endmacro %}
{% macro integer(reg, value) %}
    SET {{reg}} CR0 ;;
{% for shift in [16,8,0] %}
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
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR1 CR0 ;;
    B batch ;;
init:
{% if padded %}
    SET LR13 LR10 ;;
{% endif %}
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR12 {{cr.rows}} ;;
    LD.MULT R0 LR0 {{cr.w}} ;;
    MULT.VE LR0 CR0 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ;;
    DEC LR2 1 {% if chunks <= 4 %}; DEC LR8 1{% endif %} ;;
{% if chunks <= 4 %}
    SET LR14 {{cr.slot}} ; SET LR15 {{cr.slot}} ; SET LR10 {{cr.slot}} ;;
    ADD LR15 LR15 LR14 ;;
    ADD LR10 LR10 LR15 ;;
{% endif %}
    B row ;;
batch:
    {{ integer('LR11', out0_d1) }}
    BEQ LR1 CR0 init ;;
    SET LR4 CR0 ; SET LR5 LR1 ;;
batch_wrap:
    BLT.S LR5 {{cr.slot}} row ;;
    DEC LR5 128 ; INC LR4 1 ; B batch_wrap ;;
row:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR9 CR0 ;;
    DEC LR9 1 ;;
{% if chunks <= 4 %}
{% for i in range(chunks) %}
    LD.MULT.CYCLIC LR8 {{cr.in0}} {{['LR0','LR14','LR15','LR10'][i]}} ; INC LR8 1 ;;
{% endfor %}
{% endif %}
channel:
    LD.MULT R0 LR6 {{cr.in1}} ;;
    MULT.EE LR7 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; AGG.SUM LR3 {{cr.one}}.L ; LD.MULT R0 LR9 {{cr.w}} ; INC LR9 1 ;;
{% if chunks <= 4 %}
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR3 {{cr.one}}.L ; LD.MULT R0 LR9 {{cr.w}} ; INC LR9 1 ;;
{% for i in range(chunks) %}
    {{ product(['LR0','LR14','LR15','LR10'][i]) }} {% if i + 1 < chunks %}; LD.MULT R0 LR9 {{cr.w}} ; INC LR9 1{% endif %} ;;
{% endfor %}
{% else %}
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR3 {{cr.one}}.L ; SET LR14 LR8 ; SET LR15 {{cr.chunks}} ;;
    DEC LR14 1 ;;
k_tile:
    LD.MULT.CYCLIC LR14 {{cr.in0}} LR0 ; INC LR14 1 ;;
    LD.MULT R0 LR9 {{cr.w}} ; INC LR9 1 ; DEC LR15 1 ;;
    {{ product('LR0') }} ; BNE LR15 CR0 k_tile ;;
{% endif %}
    INC LR3 1 ; ADD LR6 LR6 {{cr.res_step}} {% if remainder %}; INC LR7 {{remainder}}{% endif %} ;;
    BLT.S LR3 {{cr.slot}} kept ;;
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR2 ; INC LR2 1 ; SET LR3 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ;;
kept:
    BEQ LR9 {{cr.last_weight}} next_row ;;
{% if remainder %}
    BLT.S LR7 {{cr.slot}} channel ;;
    DEC LR7 128 ; INC LR6 1 ;;
{% endif %}
    B channel ;;
next_row:
    DEC LR12 1 {% if chunks > 4 %}; ADD LR8 LR8 {{cr.chunks}}{% endif %} ;;
    DEC LR11 1 ; BNE LR11 CR1 advance ;;
{% if padded %}
    SET LR11 LR13 ; MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.SUB ;;
pad:
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} CR9.H {{cr.qf_out0}}.L {{cr.out0}} LR2 ; INC LR2 1 ; DEC LR11 1 ; BNE LR11 CR1 pad ;;
{% endif %}
    BEQ LR12 CR0 done ;;
    INC LR1 1 ; B batch ;;
advance:
{% if in0_d0 < 256 %}
    INC LR5 {{in0_d0}} ;;
{% else %}
    {{ integer('LR7', in0_d0) }}
    ADD LR5 LR5 LR7 ;;
{% endif %}
batch_carry:
    BLT.S LR5 {{cr.slot}} row ;;
    DEC LR5 128 ; INC LR4 1 ; B batch_carry ;;
done:
    HALT ;;
