{#- Reduce one spatial window with all channels in parallel. -#}
{% macro reduce(op) %}MULT.VE LR0 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.MAX{{ op }}{% endmacro %}
{% macro setnum(reg, value) %}
    SET {{reg}} CR0 ;;
    {% if value >= 16384 %}
    INC {{reg}} {{value // 16384}} ;;
    {% for i in range(7) %} ADD {{reg}} {{reg}} {{reg}} ;; {% endfor %}
    {% endif %}
    {% if value >= 128 %}
    {% if (value // 128) % 128 %} INC {{reg}} {{(value // 128) % 128}} ;; {% endif %}
    {% for i in range(7) %} ADD {{reg}} {{reg}} {{reg}} ;; {% endfor %}
    {% endif %}
    {% if value % 128 %} INC {{reg}} {{value % 128}} ;; {% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR7 CR0 ;;
batch:
    SUB LR3 LR0 {{ cr.padding }} ; SET LR5 CR0 ; SET LR8 LR1 ;;
out_y:
    SUB LR4 LR0 {{ cr.padding }} ; SET LR6 CR0 ;;
out_x:
    ADD LR13 LR3 {{ cr.k }} ; ADD LR14 LR4 {{ cr.k }} ;;
    BLT.S LR13 {{ cr.in0_d2 }} y_end ;;
    SET LR13 {{ cr.in0_d2 }} ;;
y_end:
    BLT.S LR14 {{ cr.in0_d3 }} x_end ;;
    SET LR14 {{ cr.in0_d3 }} ;;
x_end:
    SET LR9 LR3 ; SET LR10 LR8 ; SET LR11 LR4 ;;
    BGE.S LR11 CR0 clip_top ;;
    SET LR11 CR0 ;;
clip_top:
    BGE.S LR9 CR0 seed ;;
    INC LR9 1 ; ADD LR10 LR10 {{ cr.in0_d3 }} ; BEQ LR0 CR0 clip_top ;;
seed:
    # Seed from the first real pixel so padding never wins a signed maximum.
    ADD LR12 LR10 LR11 ; LD.MULT R0 LR12 {{ cr.in0 }} ;;
    {{ reduce('.FIRST') }} ;;
window_y:
    SET LR11 LR4 ;;
    BGE.S LR11 CR0 window_x ;;
    SET LR11 CR0 ;;
window_x:
    ADD LR12 LR10 LR11 ; LD.MULT R0 LR12 {{ cr.in0 }} ; INC LR11 1 ;;
    {{ reduce('') }} ; BLT.S LR11 LR14 window_x ;;
    INC LR9 1 ; ADD LR10 LR10 {{ cr.in0_d3 }} ;;
    BLT.S LR9 LR13 window_y ;;
    ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ; ADD LR4 LR4 {{ cr.stride }} ;;
    BLT.S LR6 {{ cr.out0_d3 }} out_x ;;
    INC LR5 1 ; ADD LR3 LR3 {{ cr.stride }} ; ADD LR8 LR8 {{ cr.vertical_step }} ;;
    BLT.S LR5 {{ cr.out0_d2 }} out_y ;;
    INC LR2 1 ; ADD LR1 LR1 LR15 ;;
    {{setnum('LR14', out0_d0)}}
    BLT.S LR2 LR14 batch ;;

    # Gather each column of pooled pixels into output height lanes.
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR10 CR0 ;;
    SET LR1 CR0 ;;
batch_out:
    SET LR4 CR0 ;;
channel_out:
    SET LR5 CR0 ;;
column_out:
    ADD LR6 LR9 LR5 ; SET LR13 CR0 ;;
chunk_out:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR7 CR0 ;;
    {{setnum('LR11', 128)}}
    MULT.EE LR0 CR0 0 LR0 {{cr.valid}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ;;
gather:
    LD.MULT R0 LR6 {{cr.tmp}} ;;
    MULT.EE LR4 CR1 0 LR0 {{cr.valid}}.L {{cr.qf_in0}}.L ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR7 1 ; INC LR13 1 ;;
    ADDBI LRD2 1 ; ADD LR6 LR6 {{cr.out0_d3}} ;;
    BEQ LR7 LR11 chunk_full ;;
    BLT.S LR13 {{cr.out0_d2}} gather ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{cr.valid}}.H {{cr.qf_out0}}.L {{cr.out0}} LR8 ;;
    INC LR8 1 ; B column_end ;;
chunk_full:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{cr.valid}}.L {{cr.qf_out0}}.L {{cr.out0}} LR8 ;;
    INC LR8 1 ; BLT.S LR13 {{cr.out0_d2}} chunk_out ;;
column_end:
    INC LR5 1 ;;
    BLT.S LR5 {{cr.out0_d3}} column_out ;;
    INC LR4 1 ; {{setnum('LR14', out0_d1)}}
    BLT.S LR4 LR14 channel_out ;;
    {{setnum('LR14', out0_d2 * out0_d3)}}
    ADD LR9 LR9 LR14 ; INC LR10 1 ;;
    {{setnum('LR14', out0_d0)}}
    BLT.S LR10 LR14 batch_out ;;
    HALT ;;
