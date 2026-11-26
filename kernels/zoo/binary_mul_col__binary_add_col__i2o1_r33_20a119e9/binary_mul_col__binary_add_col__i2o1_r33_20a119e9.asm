{# LR6 selects the channel chunk in both constants. #}
{% macro row(ds, advance, branch) %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR3 1 ;;
    LD.MULT.CYCLIC LR6 {{ cr.c0 }} LR0 ; INC LR2 1 ;;
    LD.MULT R1 LR6 {{ cr.c1 }} ; MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ advance }} ;;
    LD.MULT.CYCLIC LR6 {{ cr.c2 }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 {{ ds }} {{ cr.qf_c1 }}.L ; ACC.ADD ;;
    LD.MULT R1 LR6 {{ cr.c3 }} ;;
    MULT.VE LR1 CR1 0 LR0 {{ ds }} {{ cr.qf_c1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; {{ branch }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    INC LR1 128 ; DEC LR3 1 ; INC LR8 1 ;;
pixel:
    SET LR6 CR0 ; SET LR4 {{ cr.cb }} ;;
    BEQ LR4 LR8 tail ;;
chunk:
    {{ row(cr.ds_pair ~ '.H', 'DEC LR4 1', 'INC LR6 1 ; BNE LR4 LR8 chunk') }}
tail:
    {{ row(cr.ds_pair ~ '.L', 'INC LR5 1', 'BLT.S LR5 ' ~ cr.pixels ~ ' pixel') }}
    HALT ;;
