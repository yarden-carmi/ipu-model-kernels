{# Each RHS row contains two adjacent K-vectors. Load it once per pair;
   the cyclic window selects the second vector without unpacking. #}
{% macro dot(lane, format) %}
    MULT.RC.VV {{ lane }} R0 0 LR15 {{ cr.ds }}.L {{ format }}.L ; AGG.SUM.FIRST LR10 {{ cr.ds }}.L
{%- endmacro %}
    SET LR2 {{ cr.groups }} ; SET LR14 {{ cr.lanes }}.L ; DEC LR13 1 ;;
group:
    SET LR3 LR1 ; SET LR4 {{ cr.lanes }}.H ; SET LR5 {{ cr.heads }} ;;
head:
    SET LR6 {{ cr.sizes }}.H ;;
row:
    SET LR7 LR3 ; SET LR8 LR4 ; SET LR10 CR0 ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR15 ; BEQ LR8 CR0 first ;;
    B second ;;
pair:
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR15 ;;
first:
    {{ dot('LR15', cr.qf_in0) }} ;;
    INC LR10 1 ;;
    BEQ LR10 {{ cr.sizes }}.L end_first ;;
second:
    {{ dot('LR14', cr.qf_in1) }} ; INC LR7 1 ;;
    INC LR10 1 ; SET LR8 CR0 ;;
    BLT.S LR10 {{ cr.sizes }}.L pair ;;
    B store ;;
end_first:
    SET LR8 LR14 ;;
store:
    INC LR13 1 ; INC LR0 1 ; DEC LR6 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ; BGT.S LR6 CR0 row ;;
    SET LR3 LR7 ; SET LR4 LR8 ; DEC LR5 1 ;;
    BGT.S LR5 CR0 head ;;
    ADD LR1 LR1 {{ cr.group_step }} ; DEC LR2 1 ;;
    BGT.S LR2 CR0 group ;;
    HALT ;;
