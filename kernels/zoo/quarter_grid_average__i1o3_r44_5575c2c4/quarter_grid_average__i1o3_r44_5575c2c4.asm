{% macro pixel(first, advance) %}
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.VE LR9 {{ cr.weight_fp32 if format == 'fp32' else cr.weight }} 0 LR9 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} {% if advance %}; INC LR6 1 {% endif %};;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR9 CR0 ;;
batch:
    SET LR3 LR1 ; SET LR4 CR0 ;;
out_y:
    SET LR5 LR3 ; SET LR7 CR0 ;;
out_x:
    SET LR8 LR5 ;;
{% for y in range(4) %}
    SET LR6 LR8 ;;
{% for x in range(4) %}
    {{ pixel(y == 0 and x == 0, x != 3) }}
{% endfor %}
{% if y != 3 %} ADD LR8 LR8 {{ cr.w }} ;; {% endif %}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR2 ;;
    INC LR2 1 ; INC LR5 2 ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.out0_d3 }} out_x ;;
    ADD LR3 LR3 {{ cr.vertical_step }} ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.out0_d2 }} out_y ;;
    ADD LR1 LR1 LR15 ; INC LR0 1 ;;
    BLT.S LR0 {{ cr.out0_d0 }} batch ;;

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR8 CR0 ;;
channel:
    SET LR5 CR0 ; SET LR9 CR0 ;;
batch_out:
    SET LR6 LR5 ; SET LR13 CR0 ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR7 CR0 ;;
    SET LR11 CR0 ;; INC LR11 128 ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.valid }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
gather:
    LD.MULT R0 LR6 {{ cr.tmp }} ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_out0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADDBI LRD2 1 ; INC LR6 1 ; INC LR7 1 ;;
    INC LR13 1 ;;
    BEQ LR7 LR11 store ;;
    BLT.S LR13 {{ cr.spatial }} gather ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; BLT.S LR13 {{ cr.spatial }} chunk ;;
    SET LR5 LR6 ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.out0_d0 }} batch_out ;;
    INC LR4 1 ; SET LR12 CR0 ;;
    {% if out0_d1 <= 127 %} INC LR12 {{out0_d1}} {% else %} INC LR12 128 {% endif %} ;;
    BLT.S LR4 LR12 channel ;;
    HALT ;;
