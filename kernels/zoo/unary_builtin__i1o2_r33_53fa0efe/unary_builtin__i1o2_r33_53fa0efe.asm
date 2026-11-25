{# Elementwise relu: with in0 lanes = its dim 1 and out0 lanes = its dim 2, the
   transposed view makes out(i,m,n) = in(i,n,m) land on the same memory row and
   lane, so each row is loaded and stored straight through. Lanes past in0's
   lane dimension are masked to 0 in the multiply. #}
{% macro compute() %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.load_active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.load_active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}

    SET LR2 CR0 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BLT.S {{ cr.penultimate }} CR0 tail ;;
row:
    {{ compute() }}
    {# The load sees the incremented index; the branch sees the old index. #}
    INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BLT.S LR2 {{ cr.penultimate }} row ;;
tail:
    {{ compute() }}
    HALT ;;
