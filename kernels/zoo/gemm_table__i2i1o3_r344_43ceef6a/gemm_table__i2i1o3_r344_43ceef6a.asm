{# Gather each spatial row of the input, then accumulate directly into the
   final width-lane rows. This avoids quantizing across unrelated channels. #}
{% set chunks = (in0_d2 + 127) // 128 %}
{% macro number(reg, value) %}{% for i in range((value + 254) // 255) %}INC {{ reg }} {{ [255, value - 255 * i] | min }} ;;{% endfor %}{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ;;
    DEC LR7 1 ;;
gather_row:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR11 CR0 ;;
    INC LR11 {{ out0_d3 }} ;;
gather_x:
{% if chunks == 2 %}
    ADD LR5 LR4 CR1 ; LD.MULT R1 LR5 {{ cr.in0 }} ;;
{% endif %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.EE LR6 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; DEC LR11 1 ;;
    INC LR6 1 ; ADDBI LRD2 1 ;;
    BLT.S LR6 {{ cr.in0_d2 }} gather_advance ;;
    SET LR6 CR0 ; INC LR4 {{ chunks }} ;;
gather_advance:
    BNE LR11 CR0 gather_x ;;
    ACTIVATE.QUANTIZE identity {{ cr.width_ds }}.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR7 ; INC LR7 1 ; DEC LR8 1 ;;
    BNE LR8 CR0 gather_row ;;

    SET LR0 CR0 ; SET LR4 CR0 ;;
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR14 CR0 ;;
    {{ number('LR14', n) }}
    SET LR11 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR11 ;;
    INC LR11 1 ;;
{% endfor %}
output_channel:
    SET LR12 CR0 ; SET LR8 CR0 ;;
    {{ number('LR8', out0_d2) }}
output_row:
    SET LR4 LR13 ; SET LR5 LR12 ; SET LR10 CR0 ;;
    DEC LR4 1 ; SUB LR5 LR5 {{ cr.height }} ;;
    {{ number('LR10', k) }}
    LD.MULT R0 LR4 {{ cr.coeff }} ; INC LR4 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR4 {{ cr.coeff }} ; INC LR4 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ; ADD LR5 LR5 {{ cr.height }} ;;
tap:
    LD.MULT R0 LR4 {{ cr.coeff }} ; INC LR4 1 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR4 {{ cr.coeff }} ; INC LR4 1 ; BEQ LR10 CR1 last_tap ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ; ADD LR5 LR5 {{ cr.height }} ; DEC LR10 1 ; B tap ;;
last_tap:
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE generic {{ cr.width_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; INC LR9 1 ; INC LR12 1 ; DEC LR8 1 ;;
    BNE LR8 CR0 output_row ;;
    SET LR13 LR4 ; DEC LR14 1 ;;
    INC LR13 1 ;;
    BNE LR14 CR0 output_channel ;;

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR8 CR0 ;;
    DEC LR4 1 ;;
    {{ number('LR8', n) }}
skip_channel:
    SET LR9 CR0 ; SET LR10 LR5 ;;
    {{ number('LR9', out0_d2) }}
skip_row:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR11 CR0 ;;
    INC LR11 {{ out0_d3 }} ;;
skip_x:
    LD.MULT R0 LR10 {{ cr.in1 }} ;;
    MULT.EE LR6 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR10 LR10 {{ lr.tiles }} ; DEC LR11 1 ;;
    ADDBI LRD2 1 ; BNE LR11 CR0 skip_x ;;
    ACTIVATE.QUANTIZE identity {{ cr.width_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR4 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 skip_row ;;
    INC LR6 1 ; DEC LR8 1 ;;
    BEQ LR8 CR0 done ;;
    BLT.S LR6 {{ cr.full_count }} skip_channel ;;
    SET LR6 CR0 ; INC LR5 1 ; B skip_channel ;;
done:
    HALT ;;
