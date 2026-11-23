{# Paired coarse/residual coefficient rows, streamed with one-row lookahead. #}
{% macro part(src, acc, extra='') %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; {{ acc }} ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 {{ extra }} ;;
{% endmacro %}
{% macro chunk(limit, label) %}
    INC LR2 1 ; SET LR9 LR1 ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{{ label }}:
    {{ part('LR9', 'ACC.ADD', '; INC LR9 1') }}
    {{ part('LR9', 'ACC.ADD', '; BLT.S LR9 ' ~ limit ~ ' ' ~ label) }}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    DEC LR1 1 ; DEC LR3 1 ; SET LR4 CR0 ;;
    SET LR5 LR1 ; SET LR11 {{ cr.NB }} ;;
    DEC LR11 1 ;;
row:
    SET LR8 LR1 ; SET LR6 CR0 ;;
block:
    SET LR2 LR5 ; SET LR7 CR0 ;;
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 ;;
    {{ part('CR1', 'ACC.ADD.FIRST') }}
    {{ part('CR1', 'ACC.ADD') }}
    BLT.S LR7 {{ cr.Km1 }} full ;;
    BNE CR1 CR0 tail ;;
full:
    {{ chunk(cr.fm1, 'full_channels') }}
    INC LR7 1 ;;
    BLT.S LR7 {{ cr.Km1 }} full ;;
tail:
    {{ chunk(cr.cm1, 'tail_channels') }}
    {# Rewind the lookahead; fold appends a zero guard to the stream. #}
    DEC LR8 1 ;;
    BLT.S LR6 LR11 store_full ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} CR14.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ;;
    INC LR4 1 ; ADD LR5 LR5 {{ cr.K }} ;;
    BLT.S LR4 {{ cr.m }} row ;;
    HALT ;;
store_full:
    ACTIVATE.QUANTIZE {{ act_out0 }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; INC LR6 1 ; BLT.S LR6 {{ cr.NB }} block ;;
