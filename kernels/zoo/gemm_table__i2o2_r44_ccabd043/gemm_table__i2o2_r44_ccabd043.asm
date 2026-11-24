{% macro load_coeff() %}
    INC LR6 5 ; LD.MULT R0 LR6 {{ cr.coeff }} ;;
{% endmacro %}
{% macro mac(index) %}
    MULT.RC.VE LR0 {{ index }} 0 LR0 {{ cr.out_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{% endmacro %}
{% macro bias_part(index, op) %}
    MULT.EE {{ index }} CR1 0 LR0 {{ cr.out_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR6 CR0 ;;
    DEC LR4 1 ; DEC LR6 1 ; SET LR2 CR0 ;;
    SET LR15 CR0 ;;
    DEC LR15 1 ;;
{% for i in range(5) %}
    INC LR6 1 ; LD.LUT {{ i }} {{ cr.lut }} LR6 ;;
{% endfor %}
    SET LR12 CR0 ;;
batch:
    SET LR5 CR0 ; SET LR11 CR0 ;;
    DEC LR5 1 ;;
channel:
    SET LR3 LR2 ; SET LR10 CR0 ;;
column:
    SET LR6 LR5 ; SET LR7 CR0 ; SET LR8 {{ cr.row_width }} ;;
    {{ load_coeff() }}
    SET LR14 LR6 ;;
    {{ bias_part('LR0', 'ACC.ADD.FIRST') }} ; SET LR9 CR1 ; DEC LR14 1 ; LD.MULT R1 LR14 {{ cr.coeff }} ;;
{% for i in range(3) %}
    {{ bias_part('LR8', 'ACC.ADD') }} ; DEC LR14 1 ; LD.MULT R1 LR14 {{ cr.coeff }} ;;
{% endfor %}
    {{ bias_part('LR8', 'ACC.ADD') }} ; LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ; INC LR7 1 ;;
weight:
    {{ mac('LR7') }} ; INC LR8 1 ; ADD LR14 LR6 LR15 ; LD.MULT R1 LR14 {{ cr.coeff }} ;;
{% for i in range(3) %}
    {{ mac('LR8') }} ; DEC LR14 1 ; LD.MULT R1 LR14 {{ cr.coeff }}{% if loop.last %} ; BEQ LR9 {{ cr.k }} finish{% endif %} ;;
{% endfor %}
    {{ mac('LR8') }} ; INC LR7 1 ; INC LR9 1 ; INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ; BLT.S LR7 {{ cr.last_lane }} weight ;;
    SET LR7 CR0 ; SET LR8 {{ cr.last_lane }} ;;
    {{ load_coeff() }}
    BNE CR0 CR1 weight ;;
finish:
    {{ mac('LR8') }} ; INC LR4 1 ; INC LR10 1 ; ACTIVATE.QUANTIZE generic {{ cr.out_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR3 1 ; BLT.S LR10 {{ cr.in0_d3 }} column ;;
    INC LR11 1 ; ADD LR5 LR5 {{ cr.coeff_rows }} ;;
    BLT.S LR11 {{ cr.n }} channel ;;
    INC LR12 1 ; ADD LR2 LR2 LR13 ;;
    BLT.S LR12 {{ cr.in0_d0 }} batch ;;
    HALT ;;
