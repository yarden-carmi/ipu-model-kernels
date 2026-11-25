{% set chunks = (s0_k + 127) // 128 %}
{% set rem = s0_m % 128 %}
{% set batch = in1_d1 * in1_d2 %}
{% set direct = batch % 128 == 0 and (rem == 0 or 128 % s0_m == 0) %}
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
{% macro dot(i, next, branch='') %}
    MULT.RC.VV LR{{8+i}} R0 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR13 {{cr.full}}.L {% if next %}; LD.MULT R0 LR7 {{cr.in0}} ; INC LR7 1{% endif %} {% if i == 0 %}; INC LR13 1{% endif %} {{branch}} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{ds}}.L {{cr.qf_out0}}.L {{cr.out0}} LR6 ; ADD LR6 LR6 {{cr.blocks}} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR12 CR0 ;;
    DEC LR12 1 ; SET LR8 CR0 ;;
{% for i in range(1,chunks) %}
    ADD LR{{8+i}} LR{{7+i}} {{cr.slot}} ;;
{% endfor %}
block:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 LR1 ;;
    SET LR5 CR0 ; SET LR6 LR1 ; INC LR1 1 ;;
    DEC LR3 1 ; SUB LR6 LR6 {{cr.blocks}} ;;
{% if not direct %}
{% for i in range(7) %}
    ADD LR4 LR4 LR4 ;;
{% endfor %}
{% else %}
    SET LR14 {{cr.slot}} ;;
{% if rem %}
    SET LR14 CR0 ;;
    INC LR14 {{rem}} ;;
{% endif %}
    DEC LR14 {{3 if chunks == 1 else 2}} ;;
{% endif %}
channel:
{% if direct %}
    LD.MULT R0 LR4 {{cr.in1}} ; SET LR7 LR12 ; SET LR13 CR0 ;;
    MULT.VE LR5 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR3 {{cr.w}} ; INC LR3 1 ; DEC LR13 1 ;;
{% else %}
    # Convert the flat as-strided residual address to batch-padded storage.
    SET LR5 LR4 ; SET LR15 CR0 ;;
res_batch:
    BLT.S LR5 {{cr.batch_size}} res_row ;;
    SUB LR5 LR5 {{cr.batch_size}} ; ADD LR15 LR15 {{cr.batch_rows}} ; B res_batch ;;
res_row:
    BLT.S LR5 {{cr.slot}} res_start ;;
    SUB LR5 LR5 {{cr.slot}} ; INC LR15 1 ; B res_row ;;
res_start:
    LD.MULT R0 LR15 {{cr.in1}} ;;
    MULT.VE LR0 CR0 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.ADD.FIRST ; SET LR14 LR4 ; SET LR13 CR0 ;;
    # One lane per position. Only one output row is live.
res_lane:
    MULT.EE LR5 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.RESHAPE LRD0 LRD13 7 ;
    INC LR13 1 ; INC LR14 1 ;;
{% if rem %}
    BNE LR1 {{cr.blocks}} res_full ;;
    SET LR7 CR0 ;;
    INC LR7 {{rem}} ;;
    BEQ LR13 LR7 res_done ;;
res_full:
{% endif %}
    BEQ LR13 {{cr.slot}} res_done ;;
    # Remap at a row or batch boundary (including short batch tails).
    SET LR5 LR14 ; SET LR15 CR0 ;;
res_next_batch:
    BLT.S LR5 {{cr.batch_size}} res_next_row ;;
    SUB LR5 LR5 {{cr.batch_size}} ; ADD LR15 LR15 {{cr.batch_rows}} ; B res_next_batch ;;
res_next_row:
    BLT.S LR5 {{cr.slot}} res_next_load ;;
    SUB LR5 LR5 {{cr.slot}} ; INC LR15 1 ; B res_next_row ;;
res_next_load:
    LD.MULT R0 LR15 {{cr.in1}} ; B res_lane ;;
res_done:
    LD.MULT R0 LR3 {{cr.w}} ; INC LR3 1 ; SET LR7 LR12 ;;
    SET LR13 CR0 ;;
    DEC LR13 1 ;;
{% endif %}
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD {% if not direct %}; SET LR14 {{cr.slot}}{% endif %} ;;
{% if not direct %}
{% if rem %}
{% if s0_m > 128 %}
    BLT.S LR1 {{cr.blocks}} limit_ready ;;
{% endif %}
    SET LR14 CR0 ;;
    INC LR14 {{rem}} ;;
limit_ready:
{% endif %}
    DEC LR14 {{3 if chunks == 1 else 2}} ;;
{% endif %}
{% for i in range(chunks) %}
    LD.MULT.CYCLIC LR3 {{cr.w}} LR{{8+i}} ; INC LR3 1 ;;
{% endfor %}
    LD.MULT R0 LR7 {{cr.in0}} ; INC LR7 1 {% if rem == 1 %}; BLT.S LR14 CR0 drain{% endif %} ;;
position:
{% for i in range(chunks) %}
{{ dot(i, true, '; BLT.S LR13 LR14 position' if i == chunks - 1 else '') }}
{% endfor %}
drain:
{% for i in range(chunks) %}
{{ dot(i, i < chunks - 1) }}
{% endfor %}
{% if rem and s0_m > 128 %}
    BEQ LR1 {{cr.blocks}} store_tail ;;
{{ store(cr.full) }}
    B advance ;;
store_tail:
{% endif %}
{{ store(cr.tail if rem else cr.full) }}
advance:
    INC LR2 1 ;;
    BEQ LR2 {{cr.s0_n}} next_block ;;
{% if direct and rem %}
    INC LR5 {{rem}} ;;
    BLT.S LR5 {{cr.slot}} channel ;;
    SET LR5 CR0 ; INC LR4 1 ; B channel ;;
{% elif direct %}
{% if s0_m // 128 <= 255 %}
    INC LR4 {{s0_m // 128}} ; B channel ;;
{% else %}
{{ integer('LR15', s0_m // 128) }}
    ADD LR4 LR4 LR15 ; B channel ;;
{% endif %}
{% else %}
{{ integer('LR15', s0_m) }}
    ADD LR4 LR4 LR15 ; B channel ;;
{% endif %}
next_block:
    BEQ LR1 {{cr.blocks}} done ;;
{{ integer('LR15', 128 * chunks) }}
    ADD LR12 LR12 LR15 ; B block ;;
done:
    HALT ;;
