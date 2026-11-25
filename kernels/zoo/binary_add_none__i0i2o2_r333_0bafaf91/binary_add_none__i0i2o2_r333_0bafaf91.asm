{% set step = out0_d0 * out0_d1 %}
{% set width = (in0_d0 * in0_d1 + 127) // 128 %}
{% set dc = step % in0_d2 %}
{% set dj = (step // in0_d2) * in0_d0 %}
{% set full = cr.ds_pair ~ '.L' %}
{% macro literal(reg, n) %}
    SET {{ reg }} CR0 ;;
{% for bit in range(21, -1, -1) if 2**bit <= n %}
{% if bit < 21 and 2**(bit+1) <= n %}
    ADD {{ reg }} {{ reg }} {{ reg }} ;;
{% endif %}
{% if (n // 2**bit) % 2 %}
    INC {{ reg }} 1 ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro inc(reg, n) %}
{% if n < 256 %}
    INC {{ reg }} {{ n }} ;;
{% else %}
    {{ literal('LR13', n) }}
    ADD {{ reg }} {{ reg }} LR13 ;;
{% endif %}
{% endmacro %}
{% macro store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endmacro %}

// The view's flat address is i + d0*j + d0*d1*k. Decode it into
// the source's row-major (a,b,c), then read packed (c,b,a).
// LR6=c, LR7=b*in0_d0, LR8=a, LR9=c*width.
batch:
    SET LR12 LR1 ; SET LR5 CR0 ;;
row:
    SET LR6 LR12 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; SET LR15 {{ cr.out0_d2 }} ;;
seed_c:
    BLT.S LR6 {{ cr.in0_d2 }} seed_plane ;;
    SUB LR6 LR6 {{ cr.in0_d2 }} ; INC LR7 {{ in0_d0 }} ; B seed_c ;;
seed_plane:
    BLT.S LR7 {{ cr.plane_bytes }} seed_rows ;;
    SUB LR7 LR7 {{ cr.plane_bytes }} ; INC LR8 1 ; B seed_plane ;;
seed_rows:
    SET LR11 LR6 ;;
seed_mul:
    BEQ LR11 CR0 chunk ;;
    {{ inc('LR9', width) }}
    DEC LR11 1 ; B seed_mul ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR14 {{ cr.row_lanes }} ;;
    BGE.S LR15 LR14 gather ;;
    SET LR14 LR15 ;;
gather:
    ADD LR11 LR7 LR8 ; SET LR10 LR9 ;;
{% if width > 1 %}
addr_row:
    BLT.S LR11 {{ cr.row_lanes }} load ;;
    DEC LR11 128 ; INC LR10 1 ; B addr_row ;;
load:
{% endif %}
    LD.MULT R0 LR10 {{ cr.in0 }} ; DEC LR14 1 ; DEC LR15 1 ;;
    MULT.EE LR11 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; BEQ LR14 CR0 add ;;
    ADDBI LRD2 1 ;;
advance:
{% if dc %}
    {{ inc('LR6', dc) }}
    {{ inc('LR9', dc * width) }}
{% endif %}
{% if dj %}
    {{ inc('LR7', dj) }}
{% endif %}
{% if dc %}
    BLT.S LR6 {{ cr.in0_d2 }} wrap_plane ;;
    SUB LR6 LR6 {{ cr.in0_d2 }} ; SUB LR9 LR9 {{ cr.src_rows }} ; INC LR7 {{ in0_d0 }} ;;
{% endif %}
wrap_plane:
    BLT.S LR7 {{ cr.plane_bytes }} next_lane ;;
    SUB LR7 LR7 {{ cr.plane_bytes }} ; INC LR8 1 ; B wrap_plane ;;
next_lane:
    BNE LR14 CR0 gather ;;
    B chunk ;;
add:
    LD.MULT R0 LR4 {{ cr.in1 }} ; BEQ LR15 CR0 tail ;;
    {{ store(full) }}
    B advance ;;
tail:
    {{ store(cr.ds_pair ~ '.H') }}
    INC LR5 1 ; ADD LR12 LR12 {{ cr.out0_d0 }} ;;
    BNE LR5 {{ cr.out0_d1 }} row ;;
    INC LR1 1 ;;
    BNE LR1 {{ cr.out0_d0 }} batch ;;
    HALT ;;
