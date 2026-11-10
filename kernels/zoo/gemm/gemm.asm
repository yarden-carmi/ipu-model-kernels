{#- gemm.asm -- y = a @ w^T (+ b), one parameterised program for every (m, k, n)
    of the tile: m, n <= 128 (a row of R_ACC is one token's 128 outputs) and k
    <= 128 * 23 (a vector is ceil(k / 128) XMEM rows, contracted chunk by
    chunk). A call wider than the tile in an independent dimension is the same
    kernel launched once per tile: tokens for m, output channels for n.

    Layouts (kernel.toml has the CR map; every operand is a ROW number)
    - a, token-major: rows i * chunks + c hold token i's elements
      c * 128 .. c * 128 + 127, zero-padded past k by the packer.
    - w, output-major: rows j * chunks + c hold channel j's same slice of
      weights; w's last logical row (rows n * chunks .. ) is padding that only
      the j loop's final prefetch reads.
    - b (when the call has one): its own region, one row, n lanes.
    - y: one row per token, the first n lanes stored.

    Dataflow
    - Per token row i: R_ACC := 0 (one word: a's row times the CR constant 0,
      ACC.ADD.FIRST). Then per chunk c and per channel j, one word:
          MULT.RC.VV  R_CYCLIC[slot1] (= w[j, c]) x R0 (= a[i, c]):
              MULT_RES[t] = w[j][c * 128 + t] * a[i][c * 128 + t];
          AGG.SUM     reduces the 128 products (the k-tail ones are 0 * 0) into
              R_ACC slot j -- a partial of y[i][j]; the next chunk's AGG.SUM
              adds onto it, so the k chunks chain inside the kernel.
      The slot counter starts at -1 and is INC'd in the word: AGG reads the
      post-INC 0..n-1 and the branch the pre-INC value (timing rules 1 and 4).
      Each word prefetches w[j+1, c] into slot1; MULT reads R_CYCLIC at cycle
      start (rule 2), so a word multiplies what the word before loaded.
    - bias: one word per row, the bias row (resident in R_CYCLIC slot2 from the
      call's single load) times the CR constant 1.0, ACC.ADD onto the slots.
    - ACTIVATE.QUANTIZE identity with CR15.H (valid_elements = n) stores the
      row: the n accumulators quantized to the case's QF with the row's own
      scale, zeros past them. R_ACC is read, never modified.
    - LRs: LR0 0; LR1 the token row; LR2 the w row to prefetch; LR3 the slot
      counter; LR4 128 and LR5 256 (the R_CYCLIC slots); LR6 a's row pointer
      (it advances one row per chunk, so it is already at the next token's
      first chunk when the chunks run out); LR7 the chunk index.
    - Words: chunks * (n + 4) + 4 per token row (one more with a bias), so the
      128 x 128 x 128 tile retires 128 * 136 + 3 = 17411 of them: a's load, the
      zero seed, the chunk index, then per chunk a's load, the slot1 prime, the
      slot counter, the n-word j loop and the chunk bookkeeping, then the bias
      add and the store.
-#}
    SET LR0 CR0 ;                             # 0: the mask shift and the priming offset
    SET LR4 {{ cr.slot1 }} ;                  # 128: the weights' R_CYCLIC slot
    SET LR5 {{ cr.slot2 }} ;;                 # 256: the bias row's slot
{% if bias %}
    LD.MULT.CYCLIC LR0 {{ cr.b }} LR5 ;;      # b -> R_CYCLIC[256..383], once per call
{% endif %}
    SET LR6 CR0 ;;                            # LR6: a's row, one row per chunk
row_loop:
    LD.MULT R0 LR6 {{ cr.a }} ;;              # a[i, 0] -> R0
    MULT.VE LR0 CR0 0 LR0 CR15.L CR14.L ;     # 0 x a[i, 0]
    ACC.ADD.FIRST ;;                          # R_ACC := 0 (every slot, once per row)
    SET LR7 CR0 ;;                            # c: the chunk index
chunk_loop:
    LD.MULT R0 LR6 {{ cr.a }} ;;              # a[i, c] -> R0
    SET LR2 LR7 ;                             # w's row of channel 0 of this chunk
    LD.MULT.CYCLIC LR2 {{ cr.w }} LR4 ;;      # w[0, c] -> R_CYCLIC[128..255]
    SUB LR3 LR0 CR1 ;;                        # the slot counter: -1, so AGG sees 0, 1, ...
j_loop:
    MULT.RC.VV LR4 R0 0 LR0 CR15.L CR14.L ;
    AGG.SUM LR3 CR15.L ;
    ADD LR2 LR2 {{ cr.chunks }} ;             # the w row the NEXT word multiplies: + one channel
    LD.MULT.CYCLIC LR2 {{ cr.w }} LR4 ;
    INC LR3 1 ;
    BLT.S LR3 {{ cr.j_limit }} j_loop ;;
    INC LR6 1 ;                               # a's next chunk (and, past the last, the next row)
    INC LR7 1 ;
    BLT.S LR7 {{ cr.c_limit }} chunk_loop ;;
{% if bias %}
    MULT.RC.VE LR5 CR1 0 LR0 CR15.L CR14.L ;  # b x 1.0, element-wise
    ACC.ADD ;;                                # onto the n accumulators
{% endif %}
    ACTIVATE.QUANTIZE identity CR15.H CR14.L {{ cr.y }} LR1 ;
    INC LR1 1 ;
    BLT.S LR1 {{ cr.i_limit }} row_loop ;;
    HALT ;;
