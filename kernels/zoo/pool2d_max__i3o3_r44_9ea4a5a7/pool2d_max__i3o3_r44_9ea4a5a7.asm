{% macro pixels(first) %}
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR10 LR4 ;;
    MULT.RC.VE LR9 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ first }} LR10 {{ cr.two }}.L ;;
    INC LR9 1 ; INC LR8 1 ; INC LR10 1 ;;
    BGE.S LR8 {{ cr.bulk }} {% if first %}first_tail_check{% else %}next_tail_check{% endif %} ;;
{% if first %}
first_pixel:
{% else %}
next_pixel:
{% endif %}
{% for i in range(4) %}
    MULT.RC.VE LR9 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ first }} LR10 {{ cr.three }}.L ;;
    INC LR9 2 ; INC LR8 1 ; INC LR10 1 ;;
{% endfor %}
    BLT.S LR8 {{ cr.bulk }} {% if first %}first_pixel{% else %}next_pixel{% endif %} ;;
{% if first %}
first_tail_check:
{% else %}
next_tail_check:
{% endif %}
    BGE.S LR8 {{ cr.out0_d3 }} {% if first %}first_pixels_done{% else %}next_pixels_done{% endif %} ;;
{% if first %}
first_tail:
{% else %}
next_tail:
{% endif %}
    MULT.RC.VE LR9 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ first }} LR10 {{ cr.three }}.L ;;
    INC LR9 2 ; INC LR8 1 ; INC LR10 1 ;;
    BLT.S LR8 {{ cr.out0_d3 }} {% if first %}first_tail{% else %}next_tail{% endif %} ;;
{% if first %}
first_pixels_done:
{% else %}
next_pixels_done:
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR13 CR0 ;;
plane:
    SET LR3 CR0 ; SET LR4 CR0 ;;
output_row:
    ADD LR5 LR3 LR3 ;;
    DEC LR5 1 ;;
    BGE.S LR5 CR0 start_ok ;;
    SET LR5 CR0 ;;
start_ok:
    ADD LR6 LR3 LR3 ;;
    INC LR6 2 ;;
    BLT.S LR6 {{ cr.in0_d2 }} end_ok ;;
    SET LR6 {{ cr.in0_d2 }} ;;
end_ok:
    SET LR7 LR5 ;;
    ADD LR11 LR1 LR7 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ;;
    {{ pixels('.FIRST') }}
    INC LR7 1 ;;
    BGE.S LR7 LR6 row_done ;;
vertical:
    ADD LR11 LR1 LR7 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ;;
    {{ pixels('') }}
    INC LR7 1 ;;
    BLT.S LR7 LR6 vertical ;;
row_done:
    INC LR3 1 ;;
    BNE LR4 CR0 store ;;
    SET LR4 {{ cr.out0_d3 }} ; BEQ CR0 CR0 output_row ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; SET LR4 CR0 ; BLT.S LR3 {{ cr.out0_d2 }} output_row ;;
    ADD LR1 LR1 {{ cr.in0_d2 }} ; INC LR13 1 ;;
    BLT.S LR13 {{ cr.planes }} plane ;;
    HALT ;;
