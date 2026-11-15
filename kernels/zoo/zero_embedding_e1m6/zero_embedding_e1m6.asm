{#- zero_embedding_e1m6: out0[tokens, dim] = 0 (ids and table ignored).

    The output is laid out as rows of 128 with dim last: rows = tokens * dim / 128.
    Initialize the accumulator to zero once using the reset R0 and CR0.
    Reuse it for every output row; no input or table reads are needed. -#}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
zero_loop:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} zero_loop ;;
    HALT ;;
