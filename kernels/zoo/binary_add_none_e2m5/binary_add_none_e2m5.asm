{#- binary_add_none_e2m5: elementwise binary add, no broadcast.
    out0 = in0 + second operand, elementwise over numel elements.
    Second operand: the constant tensor `in1` (computed at home, stored row-wise
    like in0); or, when the case gives a nonzero scalar `const`, that scalar
    broadcast to every lane (call 0: out0 = in0 + 1.0).

    Layout: in0 is read "as stored": ceil(numel/128) rows of 128 consecutive
    elements. out0 keeps dimension 2 along the 128 lanes and dimensions 0,1 in
    row order, which for numel a multiple of 128 is exactly the same flat
    row-major packing, so out0 row r is the elementwise sum of in0 row r and
    the matching row of the second operand.

    Dataflow: every path into the accumulator crosses the multiplier, so each
    addend passes through a x1.0 identity multiply (idiom A2). R_ACC holds the
    running row sum and ACTIVATE.QUANTIZE identity stores it, quantizing the
    row to the case format (fp8_e2m5, QF half CR14.L) on the way out. -#}

{% if const != 0 %}
{#- Scalar path: R_CYCLIC holds a row of ones once; ones x const broadcasts the
    scalar into MULT_RES for the ACC.ADD. -#}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; INC LR1 1 ;;
    MULT.RC.VE LR0 {{ cr.const }} 0 LR0 {{ cr.ds }}.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; BLT.S LR1 {{ cr.rows }} loop ;;
{% else %}
{#- Tensor path: in0 row into R0, in1 row into R1, each through x1.0.
    LOAD reads its LR offset at end of cycle (IPU ARCH 6.2/6.3), so the row
    counter LR1 is incremented in the load-free multiply word, never beside a
    load, or every load would shift by one row. -#}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR4 {{ cr.ra_r1 }} ;;
loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; INC LR1 1 ;;
    MULT.VE LR4 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; BLT.S LR1 {{ cr.rows }} loop ;;
{% endif %}
    HALT ;;
