{% set pitch = 2 * ((in0_d1 + 63) // 64) %}
{% set step_c = (4 * in0_d1) % in0_d2 %}
{% set step_lane = 4 * ((4 * in0_d1) // in0_d2) %}
{% macro store(mask) %}
    LD.MULT R0 LR4 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; SET LR2 CR0 ; SET LR3 CR0 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
{% if step_c * pitch > 255 %}
{% for i in range(pitch) %}
    ADD LR1 LR1 {{ cr.step }}.L ;;
{% endfor %}
{% endif %}
// The view advances by 4*B flat elements per output lane. Track the
// stored c coordinate, physical row, and lane by their deltas.
row:
    SET LR8 LR5 ; SET LR9 CR0 ; SET LR13 CR0 ;;
divide_c:
    BLT.S LR8 {{ cr.in0_d2 }} got_c ;;
    SUB LR8 LR8 {{ cr.in0_d2 }} ; INC LR9 1 ; B divide_c ;;
got_c:
    SET LR10 CR0 ;;
divide_b:
    BLT.S LR9 {{ cr.pack_dims }}.L got_b ;;
    SUB LR9 LR9 {{ cr.pack_dims }}.L ; INC LR10 1 ; B divide_b ;;
got_b:
    SET LR11 CR0 ; ADD LR7 LR9 LR9 ;;
{% for i in range(pitch) %}
    ADD LR11 LR11 LR8 ;;
{% endfor %}
    ADD LR7 LR7 LR7 ;;
    ADD LR7 LR7 LR10 ; SET LR6 CR0 ;;
    SET LR9 LR7 ; B normalize_lane ;;
next_pack_row:
    DEC LR7 128 ; INC LR11 1 ; INC LR6 1 ;;
normalize_lane:
    // Issue the gather load alongside the lane check. If the lane is
    // outside this row, the next pass replaces the speculative load.
    LD.MULT R0 LR11 {{ cr.in0 }} ; BGE.S LR7 {{ cr.pack_dims }}.H next_pack_row ;;
element:
    MULT.EE LR7 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR13 1 ;;
    ADDBI LRD2 1 ; BEQ LR13 {{ cr.in0_d2 }} last_chunk ;;
    // Both paths need the next input address. Do that work in the
    // chunk-check word, even when the branch takes us to a store first.
    BLT.S LR2 CR0 full_chunk {% if step_c %}; ADD LR8 LR8 {{ cr.step }}.L ; {% if step_c * pitch <= 255 %} INC LR11 {{ step_c * pitch }} {% else %} ADD LR11 LR11 LR1 {% endif %}{% endif %} ;;
advance:
{% if step_c %}
    BLT.S LR8 {{ cr.in0_d2 }} step_b {% if step_lane %}; ADD LR7 LR7 {{ cr.step }}.H ; ADD LR9 LR9 {{ cr.step }}.H {% endif %} ;;
    SUB LR8 LR8 {{ cr.in0_d2 }} ; SUB LR11 LR11 {{ cr.column_span }} ; INC LR7 4 ;;
    INC LR9 4 ;;
step_b:
{% endif %}
{% if step_lane and not step_c %}
    ADD LR7 LR7 {{ cr.step }}.H ; ADD LR9 LR9 {{ cr.step }}.H ;;
{% endif %}
{% if in0_d1 <= 32 %}
    LD.MULT R0 LR11 {{ cr.in0 }} ; BLT.S LR9 {{ cr.batch_lanes }} element ;;
{% else %}
    BLT.S LR9 {{ cr.batch_lanes }} normalize_lane ;;
{% endif %}
next_batch:
    SUB LR9 LR9 {{ cr.batch_lanes }} ; SUB LR11 LR11 LR6 ; SET LR6 CR0 ;;
    INC LR9 1 ;;
    BGE.S LR9 {{ cr.batch_lanes }} next_batch ;;
    SET LR7 LR9 ; B normalize_lane ;;
full_chunk:
    {{ store(cr.full) }}
    B advance ;;
last_chunk:
    {{ store(cr.tail) }}
    BEQ LR4 {{ cr.rows }} done ;;
    INC LR14 1 ; INC LR5 4 ;;
    BNE LR14 {{ cr.pack_dims }}.L row ;;
    SET LR14 CR0 ; INC LR15 1 ;;
    SET LR5 LR15 ; B row ;;
done:
    HALT ;;
