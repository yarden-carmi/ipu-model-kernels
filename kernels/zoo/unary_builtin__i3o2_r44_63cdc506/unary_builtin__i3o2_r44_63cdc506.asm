{# Read input rows (c,n,h//2), each holding two consecutive h values
   for a given w at lanes w and w+W. Store (n,w,c) with h in lanes. #}
{% macro pick(lane, control='') %}
    {% if control %}INC LR6 1 ;{% endif %} INC LR10 1 ; MULT.EE {{ lane }} CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR10 {{ cr.single }}.L {{ control }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR7 CR0 ;;
batch:
    SET LR2 CR0 ; SET LR5 LR4 ; SET LR8 LR7 ;;
channel:
    SET LR3 CR0 ; SET LR9 LR8 ;;
column:
    SET LR6 LR5 ; SET LR10 CR0 ; ADD LR11 LR3 {{ cr.in0_d3 }} ;;
    DEC LR10 1 ;;
pair:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    {{ pick('LR3') }}
    {{ pick('LR11', '; BLT.S LR10 ' ~ cr.last_pair ~ ' pair') }}
    INC LR3 1 ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.output_active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; BLT.S LR3 {{ cr.last_column }} next_column ;;
    INC LR2 1 ;;
    ADD LR5 LR5 {{ cr.input_channel_step }} ; INC LR8 1 ; BLT.S LR2 {{ cr.out0_d1 }} channel ;;
    INC LR1 1 ;;
    ADD LR4 LR4 {{ cr.input_batch_step }} ; ADD LR7 LR7 {{ cr.output_batch_step }} ; BLT.S LR1 {{ cr.in0_d0 }} batch ;;
    HALT ;;
next_column:
    ADD LR9 LR9 {{ cr.out0_d1 }} ; BEQ LR0 CR0 column ;;
