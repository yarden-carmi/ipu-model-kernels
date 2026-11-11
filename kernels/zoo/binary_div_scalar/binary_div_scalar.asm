{#- binary_div_scalar.asm -- y = a / b, b one scalar broadcast over the rows.

    Layout (kernel.toml's [abi]; every operand is a ROW number, one row = 128
    lanes): a and y are ceil(numel/128) rows each, row i holding elements
    128i .. 128i+127, lanes past numel zero -- the layout every activation on
    the chip uses, so y is the next kernel's input. b is one row holding the
    scalar in lane 0.

    Dataflow. The only way into R_ACC is a multiply result, and the only route
    from R_ACC back into a multiply is a store and a load, which in NX8
    quantizes to the row's grid -- so 1/b cannot be carried at full precision
    through a register. The quotient is instead split once per call:

        y = a * (r + e),   r = AaQ reciprocal of b,   e = 1 - b*r

    r is the ACTIVATE.QUANTIZE reciprocal of the broadcast scalar (all 128
    lanes of one row the same value, so the row's own quantization costs at
    most one step of r); the correction is e = (1 - b*r)/b = (1 - b*r)*r:
    b*r is an exact product, 1 - b*r an exact FP32 subtract (b*r is within
    [0.5, 2] of 1, so Sterbenz makes it exact), and the product with the
    resident r is exact; each factor is stored with the one-lane DS half, so
    it keeps ~2^-7 of its OWN magnitude and the residual 1 - b*(r+e) is
    ~2^-13 of 1/b. Each row is then two exact products a*r + a*e and one
    accumulator add, and the store's quantization is the only error the
    golden sees.

    The correction needs an exact ones row to subtract b*r from: R_ACC is
    seeded 1 by multiplying an exact ones row -- built by ACTIVATE.QUANTIZE
    exp2 of 0 (exp2(0) = 1, one distinct value, stored exactly) -- into
    R_ACC. b is then walked through the one cyclic slot the loop uses, its
    product with the resident r taken with MULT.RC.VV, and R0/R1 end as the
    two scalars: R0[0] = r (element 0 of Ra) and R1[0] = e (element 128, CR
    slot1).

    Per row, two words: word A multiplies the a row resident in the cyclic
    slot by r and initialises the accumulator, word B multiplies the same row
    by e, accumulates and stores, and carries the next row's load (MULT reads
    R_CYCLIC at cycle start, LOAD writes after -- rule 2). The last row is
    emitted straight-line, so no word loads a row past a's region; the loop's
    bound is rows-1.

    LR: LR0 0; LR1 the a row pointer; LR2 the y row being stored; LR3 the loop
    counter (one ahead); LR4 the bound; LR7 128 (R1's element 0 in Ra). The
    program sets every LR it reads and loads its own mask row, so it runs
    after another kernel as well as from reset.
-#}
{% set rows = (numel + 127) // 128 %}
{% set dsf = cr.ds ~ ".L" %}
{% set dsh = cr.ds ~ ".H" %}
{% set qfl = cr.qf ~ ".L" %}
    SET LR0 CR0 ; SET LR7 {{ cr.slot1 }} ;;               {#- 0; R1's element 0 in Ra -#}
    SET LR1 CR0 ; SET LR2 CR0 ;;                          {#- the a row pointer; the y store row -#}
    SET LR3 CR1 ;;                                        {#- the loop counter, one ahead -#}
{% if rows >= 2 %}
    SET LR4 {{ cr.bound }} ;;                             {#- rows - 1: the last row is straight-line -#}
{% endif %}
    LD.MASK LR0 {{ cr.maskr }} ;;                         {#- every lane of every multiply active -#}
    LD.MULT R0 LR0 {{ cr.b }} ;;                          {#- R0 <- the b row -#}
    MULT.EE LR0 CR1 0 LR0 {{ dsf }} {{ qfl }} ;           {#- the scalar, broadcast -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE reciprocal {{ dsf }} {{ qfl }} {{ cr.rcp }} LR0 ;;  {#- r <- 1/b -#}
    LD.MULT R1 LR0 {{ cr.rcp }} ;;                        {#- R1 <- the r row -#}
    MULT.VE LR0 CR0 0 LR0 {{ dsf }} {{ qfl }} ;           {#- zeros -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE exp2 {{ dsf }} {{ qfl }} {{ cr.ones }} LR0 ;;       {#- ones <- exp2(0) = 1 -#}
    LD.MULT.CYCLIC LR0 {{ cr.ones }} LR7 ;;               {#- cyclic[128..255] <- 1s -#}
    MULT.RC.VE LR7 CR1 0 LR0 {{ dsf }} {{ qfl }} ;
    ACC.ADD.FIRST ;;                                      {#- R_ACC <- 1s -#}
    LD.MULT.CYCLIC LR0 {{ cr.b }} LR0 ;;                  {#- cyclic[0..127] <- the b row -#}
    MULT.RC.VV LR0 R1 0 LR0 {{ dsf }} {{ qfl }} ;         {#- b*r -#}
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity {{ dsh }} {{ qfl }} {{ cr.t }} LR0 ;;      {#- t <- 1 - b*r, lane 0 -#}
    LD.MULT R0 LR0 {{ cr.t }} ;;                          {#- R0[0] <- t -#}
    LD.MULT.CYCLIC LR0 {{ cr.rcp }} LR0 ;;                {#- cyclic[0..127] <- r's -#}
    MULT.RC.VE LR0 LR0 0 LR0 {{ dsf }} {{ qfl }} ;        {#- t*r = (1-b*r)/b -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsh }} {{ qfl }} {{ cr.e }} LR0 ;;      {#- e <- the correction, lane 0 -#}
    LD.MULT R1 LR0 {{ cr.e }} ;;                          {#- R1[0] <- e -#}
    LD.MULT R0 LR0 {{ cr.rcp }} ;;                        {#- R0[0] <- r -#}
    LD.MULT.CYCLIC LR0 {{ cr.a }} LR0 ;;                  {#- prime: a[0] -> cyclic[0..127] -#}
{% if rows >= 2 %}
row_loop:
    ADD LR2 LR1 CR0 ; MULT.RC.VE LR0 LR0 0 LR0 {{ dsf }} {{ qfl }} ; ACC.ADD.FIRST ;;
    INC LR1 1 ; MULT.RC.VE LR0 LR7 0 LR0 {{ dsf }} {{ qfl }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ dsf }} {{ qfl }} {{ cr.y }} LR2 ; LD.MULT.CYCLIC LR1 {{ cr.a }} LR0 ; INC LR3 1 ; BLT.S LR3 LR4 row_loop ;;
{% endif %}
    ADD LR2 LR1 CR0 ; MULT.RC.VE LR0 LR0 0 LR0 {{ dsf }} {{ qfl }} ; ACC.ADD.FIRST ;;     {#- the last row -#}
    MULT.RC.VE LR0 LR7 0 LR0 {{ dsf }} {{ qfl }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ dsf }} {{ qfl }} {{ cr.y }} LR2 ;;
end:
    HALT ;;
