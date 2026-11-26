{% set ds = cr.active ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qs = cr.qf_in1 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set width = out0_d3 %}
{% macro load_pair() %}
    LD.MULT R0 LR10 {{ cr.coeff }} ; INC LR10 1 ;;
    LD.MULT R1 LR10 {{ cr.coeff }} ; INC LR10 1 ;;
{% endmacro %}
{% macro taps(count) %}
    SUB LR2 LR0 CR1 ; SUB LR3 LR14 CR1 ;;
{% for j in range(count) %}
    LD.MULT.CYCLIC LR5 {{ cr.spatial }} LR0 ; ADD LR5 LR5 {{ cr.stripes }} ;;
    MULT.RC.VE LR0 LR2 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR2 1 ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR3 1 ;;
{% endfor %}
{% endmacro %}

    // Stream the flattened storage in view order, skipping physical padding.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR6 {{ cr.in0_d2 }} ; SET LR8 CR0 ;;
    SET LR11 {{ cr.stripes }} ; SET LR12 {{ cr.k }} ; SET LR14 CR0 ;;
    INC LR14 128 ; SET LR9 CR0 ; DEC LR8 1 ;;
    INC LR9 {{ width }} ;;
stage_vector:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR7 LR9 ;;
    SET LR15 CR0 ;;
stage_segment:
    BNE LR6 CR0 have_logical ;;
    SET LR6 {{ cr.in0_d2 }} ; B advance_row ;;
have_logical:
    BNE LR5 LR14 have_physical ;;
advance_row:
    INC LR4 1 ; SET LR5 CR0 ;;
have_physical:
    SUB LR13 LR14 LR5 ;;
    BGE.S LR6 LR13 bounded ;;
    SET LR13 LR6 ;;
bounded:
    BLT.S LR13 LR9 gather_load ;;
    BNE LR15 CR0 gather_load ;;
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR5 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
    ADD LR5 LR5 LR9 ; SUB LR6 LR6 LR9 ; B stage_store ;;
gather_load:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
gather:
    MULT.EE LR5 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 7 ; DEC LR6 1 ; DEC LR7 1 ;;
    ADDBI LRD2 1 ; DEC LR13 1 ; INC LR5 1 ; BEQ LR7 CR0 stage_store ;;
    BNE LR13 CR0 gather ;;
    SET LR15 CR1 ; B stage_segment ;;
stage_store:
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.spatial }} LR8 ; INC LR8 1 ; DEC LR11 1 ;;
    BNE LR11 CR0 stage_vector ;;
    SET LR11 {{ cr.stripes }} ; DEC LR12 1 ; BNE LR12 CR1 stage_vector ;;

    SUB LR5 LR0 CR1 ;;
{% for segment in range(5) %}
    LD.LUT {{ segment }} {{ cr.lut }} LR5 ; INC LR5 1 ;;
{% endfor %}

    // Each stripe holds the skip channels first, then the activated GEMM.
    SUB LR8 LR0 CR1 ; SUB LR9 LR0 CR1 ; SET LR11 {{ cr.stripes }} ;;
stripe:
    SET LR7 {{ cr.n }} ;;
copy_skip:
    LD.MULT R0 LR8 {{ cr.in1 }} ; INC LR8 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qs }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.out0 }} LR9 ; INC LR9 1 ; DEC LR7 1 ; BNE LR7 CR1 copy_skip ;;
    SET LR7 {{ cr.n }} ; SUB LR10 LR0 CR1 ;;
channel:
    {{ load_pair() }}
    MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; SUB LR5 LR12 {{ cr.stripes }} ; SET LR6 {{ cr.k }} ;;
    MULT.EE LR14 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
{% if k > 32 %}
    SET LR4 CR0 ;;
    INC LR4 32 ;;
block:
    {{ load_pair() }}
    {{ taps(32) }}
    DEC LR6 32 ;;
    BLT.S LR4 LR6 block ;;
{% endif %}
    {{ load_pair() }}
    {{ taps((k - 1) % 32 + 1) }}
    ACTIVATE.QUANTIZE generic {{ ds }} {{ qo }} {{ cr.out0 }} LR9 ; INC LR9 1 ; DEC LR7 1 ; BNE LR7 CR1 channel ;;
    INC LR12 1 ; DEC LR11 1 ; BNE LR11 CR1 stripe ;;
    HALT ;;
