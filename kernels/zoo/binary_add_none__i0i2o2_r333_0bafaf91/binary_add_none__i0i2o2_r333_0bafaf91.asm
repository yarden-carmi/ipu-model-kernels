{% set full = cr.ds_pair ~ '.L' %}
{% macro normalize(c, ab, tag) %}
    BLT.S {{ c }} {{ cr.c_limit }} {{ tag }}_ab ;;
    SUB {{ c }} {{ c }} {{ cr.c_limit }} ; ADD {{ ab }} {{ ab }} {{ cr.in0_d0 }} ;;
{{ tag }}_ab:
    BLT.S {{ ab }} {{ cr.plane }} {{ tag }}_ready ;;
    SUB {{ ab }} {{ ab }} {{ cr.plane }} ;;
    INC {{ ab }} 1 ; B {{ tag }}_ab ;;
{{ tag }}_ready:
{% endmacro %}
{% macro store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ;;
{% endmacro %}

    INC LR14 128 ;;
row:
    // The view advances by d0*d1 per output lane. In storage coordinates
    // (a,b,c), keep c*width and the packed linear lane b*d0+a.
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR9 LR15 ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ; BGE.S LR9 LR14 gather ; SET LR12 LR14 ;;
    SET LR12 LR9 ;;
gather:
    SET LR10 LR7 ; SET LR11 LR6 ;;
pack_row:
    BLT.S LR10 LR14 load ;;
    DEC LR10 128 ; INC LR11 1 ; B pack_row ;;
load:
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    MULT.EE LR10 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR6 LR6 {{ cr.c_step }} ; ADD LR7 LR7 {{ cr.ab_step }} ;;
    {{ normalize('LR6', 'LR7', 'lane') }}
    DEC LR12 1 ;;
    BEQ LR12 CR0 add ; ADDBI LRD2 1 ;;
    B gather ;;
add:
    LD.MULT R0 LR8 {{ cr.in1 }} ; BGE.S LR14 LR9 tail ;;
    {{ store(full) }}
    DEC LR9 128 ; B chunk ;;
tail:
    {{ store(cr.ds_pair ~ '.H') }}
    INC LR13 1 ; SET LR10 {{ cr.in0_d0 }} ;;
    BNE LR13 {{ cr.out0_d1 }} advance ;;
    INC LR1 1 ; SET LR13 CR0 ; SET LR4 CR0 ;;
    BEQ LR1 {{ cr.in0_d0 }} finish ; SET LR5 CR0 ; SET LR10 LR1 ;;
advance:
    ADD LR4 LR4 {{ cr.width }} ; DEC LR10 1 ;;
    {{ normalize('LR4', 'LR5', 'start') }}
    BNE LR10 CR0 advance ;;
    B row ;;
finish:
    HALT ;;
