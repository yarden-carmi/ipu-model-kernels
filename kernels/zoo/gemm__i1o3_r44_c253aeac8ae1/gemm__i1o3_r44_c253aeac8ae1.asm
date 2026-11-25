{% set w = cr.w if bias else cr.w_unbiased %}
{% macro dot(reg) %}MULT.RC.VV LR0 {{ reg }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR9 {{ cr.full }}.L{% endmacro %}
{% macro bias_mac(first=false) %}MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 {{ cr.scanlines }} ;;
    SET LR3 CR0 ;;
scanline:
    SET LR4 {{ cr.n }} ;;
    SET LR5 CR0 ;;
    DEC LR5 1 ;;
feature:
    SET LR6 LR5 ;;
    SET LR7 LR1 ;;
    SET LR8 {{ cr.chunks }} ;;
{% if bias %}
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ; INC LR6 1 ;;
    {{ bias_mac(true) }} ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ; INC LR6 1 ;;
    {{ bias_mac() }} ;;
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
chunk:
    SET LR9 CR0 ;;
    LD.MULT R0 LR6 {{ w }} ; INC LR6 1 ;;
    LD.MULT R1 LR6 {{ w }} ; INC LR6 1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ; SET LR11 LR7 ; DEC LR9 1 ;;
{% if out0_d3 > 1 %}
pixel:
    {{ dot('R0') }} ; ADD LR11 LR11 {{ cr.input_chunks }} ; INC LR9 1 ;;
    {{ dot('R1') }} ; LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ; BNE LR9 {{ cr.penultimate }} pixel ;;
{% endif %}
    {{ dot('R0') }} ; INC LR9 1 ;;
    {{ dot('R1') }} ; INC LR7 1 ;;
    DEC LR8 1 ; BNE LR8 CR1 chunk ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    SET LR5 LR6 ; INC LR3 1 ; DEC LR4 1 ; BNE LR4 CR1 feature ;;
    ADD LR1 LR1 {{ cr.input_stride }} ; DEC LR2 1 ; BNE LR2 CR1 scanline ;;
    HALT ;;
