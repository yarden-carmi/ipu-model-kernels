// For output (a,b,c), the first view reads flat offset (c*B+b)*A+a.
// LR1 and LR4 track the remainder and quotient in the stored in0 plane.
// A group of A adjacent offsets cannot straddle a plane boundary.
{% set A = out0_d0 %}
{% set C = out0_d2 %}
{% set chunks = (C + 127) // 128 %}
{% macro channel(a) %}
    LD.MULT R0 LR2 {{ cr.in0 }} {% if a > 0 %}; INC LR8 1 ; INC LR9 128{% endif %} ;;
    MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR8 {{ cr.ds1 }}.L ; INC LR2 1 ;;
    MULT.RC.VE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; AGG.SUM LR8 {{ cr.ds1 }}.L ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    SET LR14 {{ cr.out0_d1 }} ; SET LR15 CR0 ;;
row_loop:
    SET LR1 LR5 ; SET LR4 CR0 ; SET LR13 LR15 ;;
    SET LR7 LR15 ;;
    INC LR7 {{ chunks }} ;;
chunk_loop:
    SET LR11 LR13 ; SET LR12 CR0 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR12 ;;
{% for a in range(1,A) %}
    ADD LR11 LR11 {{ cr.plane1 }} ; INC LR12 128 ; LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR12 ;;
{% endfor %}
    SET LR6 CR0 ; SET LR10 CR0 ; INC LR13 1 ;;
{% if C % 128 != 0 %}
    INC LR10 {{ C % 128 }} ;;
    {% if chunks > 1 %}
    BNE LR13 LR7 full_chunk ;;
    B column_loop ;;
full_chunk:
    SET LR10 CR0 ;;
    INC LR10 128 ;;
    {% endif %}
{% else %}
    INC LR10 128 ;;
{% endif %}
column_loop:
    SET LR2 LR1 ; SET LR8 CR0 ; SET LR9 LR6 ;;
{% for a in range(A) %}
    {{ channel(a) }}
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; INC LR6 1 ; ADD LR1 LR1 {{ cr.view_step }} ;;
    DEC LR10 1 ; BLT.S LR1 {{ cr.in0_rows }} no_wrap ;;
    SUB LR1 LR1 {{ cr.in0_rows }} ; INC LR4 1 ;;
no_wrap:
    BNE LR10 CR0 column_loop ;;
    BLT.S LR13 LR7 chunk_loop ;;
    INC LR5 {{ A }} ; SET LR15 LR13 ; DEC LR14 1 ;;
    BNE LR14 CR0 row_loop ;;
    HALT ;;
