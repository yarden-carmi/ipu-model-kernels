{% macro mac(scalar, first=false) -%}
MULT.RC.VE LR0 {{scalar}} 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro weight() -%}
LD.MULT.CYCLIC LR4 {{cr.w}} LR0 ; INC LR4 1
{%- endmacro %}
{% macro store(ds) -%}
ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{ds}}.L {{cr.qf_out0}}.L {{cr.out0}} LR5
{%- endmacro %}
    SET LR0 CR0 ; SET LR8 CR0 ; SET LR5 CR0 ;;
    SET LR10 {{cr.rows}} ; DEC LR5 1 ; DEC LR8 1 ;;
row:
    SUB LR4 LR0 CR1 ; SET LR6 {{cr.tiles}} ;;
tile:
    SET LR2 LR8 ; SET LR9 {{cr.chunks}} ; {{weight()}} ;;
    {{mac('CR1', true)}} ;;
chunk:
    LD.MULT R0 LR2 {{cr.in0}} ; INC LR2 1 ; DEC LR9 1 ; SET LR7 {{cr.full_end}} ;;
    BNE LR9 CR0 endpoints ;;
    SET LR7 {{cr.end}} ;;
endpoints:
    SUB LR3 LR0 CR1 ; {{weight()}} ;;
    BLT.S LR7 LR3 final_lane ;;
lane:
    {{mac('LR3')}} ; INC LR3 1 ; {{weight()}} ; BLT.S LR3 LR7 lane ;;
final_lane:
    {{mac('LR3')}} ; INC LR3 1 ; BNE LR9 CR0 chunk ;;
    LD.MULT R0 LR5 {{cr.in1}} ; INC LR5 1 ; DEC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.ADD ; BEQ LR6 CR0 tail ;;
    {{store(cr.full)}} ; B tile ;;
tail:
    {{store(cr.tail)}} ; SET LR8 LR2 ; DEC LR10 1 ;;
    BNE LR10 CR0 row ;;
    HALT ;;
