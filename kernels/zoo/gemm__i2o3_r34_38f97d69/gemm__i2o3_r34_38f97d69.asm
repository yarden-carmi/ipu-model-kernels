{# The stored last axis is row-aligned, so the contiguous NCHW view
   can be addressed directly in units of 128 spatial elements. #}
{% macro dot(prefetch=false) %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1{% if prefetch %} ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.spatial }} ; BLT.S LR3 LR7 lane{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR6 {{ cr.n }} ; DEC LR5 1 ; DEC LR4 1 ;;
channel:
    SET LR8 CR0 ; SET LR9 {{ cr.out0_d0 }} ;;
batch:
    SET LR10 LR8 ; SET LR11 {{ cr.spatial }} ;;
site:
    SET LR12 LR4 ; SET LR13 {{ cr.planes }} ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
plane:
    LD.MULT R0 LR12 {{ cr.coeff }} ; INC LR12 1 ; SUB LR2 LR10 {{ cr.spatial }} ; SET LR1 {{ cr.chunks }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
chunk:
    LD.MULT R0 LR12 {{ cr.coeff }} ; INC LR12 1 ; DEC LR1 1 ; SET LR3 CR0 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.spatial }} ; SET LR7 LR14 ; DEC LR3 1 ; BNE LR1 CR0 setup ;;
    SET LR7 {{ cr.last }} ;;
setup:
    BEQ LR7 CR0 final_lane ; DEC LR7 2 ;;
lane:
    {{ dot(true) }}
final_lane:
    {{ dot() }}
    BNE LR1 CR0 chunk ;;
    DEC LR13 1 ;;
    BNE LR13 CR0 plane ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR10 1 ; DEC LR11 1 ;;
    BNE LR11 CR0 site ;;
    ADD LR8 LR8 {{ cr.batch_stride }} ; DEC LR9 1 ;;
    BNE LR9 CR0 batch ;;
    ADD LR4 LR4 {{ cr.coeff_stride }} ; DEC LR6 1 ;;
    BNE LR6 CR0 channel ;;
    HALT ;;
