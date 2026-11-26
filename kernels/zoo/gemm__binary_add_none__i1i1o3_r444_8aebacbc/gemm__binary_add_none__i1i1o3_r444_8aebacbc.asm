{% macro mac(s, op='ADD', qf=cr.qf_in0) %}
MULT.RC.VE LR0 {{s}} 0 LR0 {{cr.valid}}.L {{qf}}.L ; ACC.{{op}}
{%- endmacro %}
{% macro nextw() %}INC LR3 1 ; LD.MULT.CYCLIC LR3 {{cr.w}} LR0{% endmacro %}
{% macro chunk(label, taps) %}
    INC LR8 1 ; LD.MULT R0 LR8 {{cr.in0}} ; SET LR4 CR0 ; SET LR6 CR0 ;;
    INC LR6 {{taps}} ; {{nextw()}} ;;
{{label}}:
    {{mac('LR4')}} ; {{nextw()}} ;;
    {{mac('LR4')}} ; DEC LR6 1 ; BEQ LR6 CR1 {{label}}_end ;;
    INC LR4 1 ; {{nextw()}} ; B {{label}} ;;
{{label}}_end:
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR12 CR0 ;;
pixel:
    SET LR3 CR0 ; SET LR8 LR1 ; LD.MULT.CYCLIC LR0 {{cr.w}} LR0 ;;
    DEC LR8 1 ;;
    {{mac('CR1','ADD.FIRST')}} ; {{nextw()}} ;;
    {{mac('CR1')}} ;;
{% if s0_k > 128 %}
    SET LR10 CR0 ;;
    INC LR10 {{(s0_k-1)//128}} ;;
chunk_loop:
    {{chunk('chunk_tap',128)}}
    DEC LR10 1 ; BNE LR10 CR1 chunk_loop ;;
{% endif %}
    {{chunk('tail_tap',(s0_k-1)%128+1)}}
    LD.MULT.CYCLIC LR12 {{cr.in1}} LR0 ;;
    {{mac('CR1',qf=cr.qf_in1)}} ; ACTIVATE.QUANTIZE identity {{cr.valid}}.L {{cr.qf_out0}}.L {{cr.tmp}} LR12 ; ADD LR1 LR1 {{cr.chunks}} ;;
    LD.MULT R0 LR12 {{cr.tmp}} ;;
    MULT.VE LR0 CR1 0 LR0 {{cr.valid}}.L {{cr.qf_out0}}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{cr.valid}}.L {{cr.qf_out0}}.L {{cr.correction}} LR12 ;;
    INC LR12 1 ;;
    BNE LR12 {{cr.pixels}} pixel ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR0 CR0 ;;
channel:
    SET LR6 CR0 ; SET LR7 CR0 ;;
group:
    MULT.EE LR0 CR0 0 LR0 {{cr.full}}.L {{cr.qf_out0}}.L ; ACC.ADD.FIRST ; SET LR8 CR0 ;;
gather:
    LD.MULT R0 LR7 {{cr.tmp}} ;;
    MULT.EE LR4 CR1 0 LR0 {{cr.full}}.L {{cr.qf_out0}}.L ; AGG.SUM LR8 {{cr.scalar}}.L ;;
    LD.MULT R0 LR7 {{cr.correction}} ;;
    MULT.EE LR4 CR1 0 LR0 {{cr.full}}.L {{cr.qf_out0}}.L ; AGG.SUM LR8 {{cr.scalar}}.L ;;
    INC LR7 1 ; INC LR8 1 ;;
    BEQ LR7 {{cr.pixels}} store ;;
    BLT.S LR8 LR15 gather ;;
store:
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR3 ;;
    INC LR3 1 ;;
    BNE LR7 {{cr.pixels}} group ;;
    INC LR4 1 ;;
    BNE LR4 LR14 channel ;;
    HALT ;;
