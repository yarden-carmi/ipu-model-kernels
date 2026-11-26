{% macro mac() -%}
MULT.RC.VE LR0 LR3 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD
{%- endmacro %}
{% macro load_next() -%}
LD.MULT.CYCLIC LR2 {{cr.in0}} LR0 ; ADD LR2 LR2 {{cr.tiles}}
{%- endmacro %}
{% macro store(ds) -%}
ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{ds}}.L {{cr.qf_out0}}.L {{cr.out0}} LR5
{%- endmacro %}
    SET LR0 CR0 ; SET LR6 CR0 ; SET LR5 CR0 ;;
    DEC LR5 1 ;;
channel:
    SET LR8 CR0 ; SET LR9 LR14 ;;
batch:
    SET LR10 LR8 ; SET LR11 {{cr.tiles}} ;;
tile:
    LD.MULT.CYCLIC LR6 {{cr.w}} LR0 ; SET LR4 LR6 ; SET LR1 {{cr.chunks}} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ; SUB LR2 LR10 {{cr.tiles}} ;;
chunk:
    LD.MULT R0 LR4 {{cr.w}} ; INC LR4 1 ; SET LR7 {{cr.full_end}} ; DEC LR1 1 ;;
    BNE LR1 CR0 preload ;;
    SET LR7 {{cr.end}} ;;
preload:
    {{load_next()}} ; SUB LR3 LR0 CR1 ;;
    BLT.S LR7 LR3 last_lane ;;
lane:
    {{mac()}} ; INC LR3 1 ; {{load_next()}} ; BLT.S LR3 LR7 lane ;;
last_lane:
    {{mac()}} ; INC LR3 1 ; BNE LR1 CR0 chunk ;;
    LD.MULT R0 LR5 {{cr.in1}} ; INC LR5 1 ; DEC LR11 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.ADD ; BEQ LR11 CR0 tail ;;
    {{store(cr.full)}} ; INC LR10 1 ; B tile ;;
tail:
    {{store(cr.tail)}} ; ADD LR8 LR8 {{cr.batchstride}} ; DEC LR9 1 ; BNE LR9 CR1 batch ;;
    ADD LR6 LR4 CR1 ; DEC LR15 1 ; BNE LR15 CR1 channel ;;
    HALT ;;
