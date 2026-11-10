{#- gemm.asm -- y = a @ w (+ b), one parameterised program for every (m, k, n).

    m tokens, k inputs, n output channels; nothing about the call is bigger than
    the tile, because the tile is a loop here. Two loops are dynamic and carry
    the call's size: the token loop (m rows of y, one per token and tile) and the
    input loop inside a k chunk (the 128 words that contract one chunk). The
    output-channel tile loop (n / 128 tiles, one row of R_ACC is one tile's 128
    channels) and the k chunk loop (a's 128-lane rows) are rendered per call,
    each copy a straight-line prologue plus the same dynamic input loop, which
    frees their counters for the inner loop's three LR slots. Only what the
    program cannot know at render time reaches it through CRs.

    Layouts (kernel.toml has the CR map; every operand is a ROW number)
    - a, token-major: rows i * chunks + c hold token i's elements
      c * 128 .. c * 128 + 127, zero-padded past k by the packer.
    - w, *input-major*: row t * wtiles + tt holds input channel t's weights for
      the output channels tt * 128 .. tt * 128 + 127. Column n pads the last
      tile's lanes, row k the input loop's last prefetch. wtiles = ceil((n+1)/128).
    - b (when the call has one): its own region, one row per output tile.
    - y: one row per token and tile, the last tile's first n lanes stored.

    Dataflow: the outer product, which is what makes one word one hundred
    twenty-eight useful MACs. Per token i, per tile tt and per input t, one word:
        MULT.RC.VE  R_CYCLIC[slot0] (= w[t, tt], 128 channels) x the scalar
                    R0[t mod 128] (= a[i, t]),
            MULT_RES[j] = w[t][tt * 128 + j] * a[i][t];
        ACC.ADD     adds the products into the tile's 128 R_ACC slots -- the
                    inputs of one output chain through the slot, so the whole of
                    k is contracted inside the kernel and no partial leaves XMEM.
    Lanes past k of a chunk multiply the packer's zeros and the short last chunk
    stops at k - 128 * (chunks - 1) inputs, so nothing is wasted there.
    Each word prefetches the next input's w row into slot 0; MULT reads
    R_CYCLIC at cycle start (timing rule 2), so a word multiplies what the word
    before loaded, and a's row rides in the chunk's prologue word.
    - bias: the tile's b row is resident in R1 for the whole tile pass, so the
      store word is also the bias add: MULT.VE of R1 by the CR constant 1.0 and
      ACC.ADD, then ACTIVATE.QUANTIZE identity in the same word.
    - the store: DS .L (128 lanes) for a full tile, DS .H for the last one
      (n - 128 * (ytiles - 1) lanes), so a row's scale never sees a lane past n.
      table_offset is a *forwarded* read, so the row's number is copied to LR14
      in the row's prologue word and this word only moves LR6 on. R_ACC is read,
      never modified.
    - LR: LR0 0; LR1 w's row; LR2 the input index (the loop counter, kept one
      ahead: -1, INC'd in the word, so the multiply sees 0, 1, ... and the branch
      the previous value -- timing rules 1 and 4); LR3 a's row, free-running
      (one per chunk, reset per tile pass); LR13 the value LR3 had when a's row
      was loaded (LOAD reads LRs forwarded, so the INC rides in the same word);
      LR4 b's row; LR5 128 (R1's offset in Ra); LR6 y's row, one ahead; LR14 the
      row being stored; LR7 the tile index (w's row for its input 0, the loop
      strides by wtiles); LR10 the token counter (m - 2 down: its branch reads
      the pre-DEC value); LR12 the tile index (y's row for its token 0).
    - Words: ytiles * (m * (k + chunks + 2) + 1) + 3 -- one per (token, tile,
      input) plus a prologue per chunk and one per row, at 128 MACs a word.
-#}
{% set chunks = (k + 127) // 128 %}
{% set has_tail = (k % 128) != 0 %}
{% set chunks_full = chunks - (1 if has_tail else 0) %}
{% set ytiles = (n + 127) // 128 %}
    SET LR0 CR0 ; SET LR5 {{ cr.slot1 }} ; SET LR12 CR0 ;;   # 0; R1's offset in Ra; the tile's y row
    SET LR7 CR0 ; SET LR4 CR0 ;;                  # this tile's index: w's row for input 0, b's row
{% for tt in range(ytiles) %}
pass{{ tt }}:
    SET LR10 {{ cr.rows_bound }} ; SET LR6 LR12 ; SET LR3 CR0 ;;   # the token loop; a's row starts here
{% if bias %}
    LD.MULT R1 LR4 {{ cr.b }} ;;                  # this tile's biases -> R1, once per pass
{% endif %}
row{{ tt }}:
    MULT.VE LR0 CR0 0 LR0 CR15.L CR14.L ;         # 0 x Ra
    ACC.ADD.FIRST ;                               # R_ACC := 0 (this tile's slots, once per row)
    LD.MULT.CYCLIC LR1 {{ cr.w }} LR0 ;           # w[0, tt] -> R_CYCLIC[0..127] (LR1, post-SET)
    SET LR1 LR7 ; SET LR14 LR6 ; ADD LR6 LR6 {{ cr.y_stride }} ;;
{% for c in range(chunks_full) %}
chunk{{ tt }}_{{ c }}:
    SET LR13 LR3 ; INC LR3 1 ; SUB LR2 LR0 CR1 ;  # the input counter: -1, so it sees 0, 1, ...
    LD.MULT R0 LR13 {{ cr.a }} ;;                 # a[i, {{ c }}] -> R0 (LR13, post-SET: LR3)
tloop{{ tt }}_{{ c }}:
    MULT.RC.VE LR0 LR2 0 LR0 CR15.L CR14.L ;      # w[t, tt] x a[i, t]: 128 channels at once
    ACC.ADD ;                                     # into the tile's 128 accumulators
    ADD LR1 LR1 {{ cr.wtiles }} ;                 # the w row the NEXT word multiplies: + one input
    LD.MULT.CYCLIC LR1 {{ cr.w }} LR0 ;
    INC LR2 1 ;
    BLT.S LR2 {{ cr.lanes_full_m2 }} tloop{{ tt }}_{{ c }} ;;
{% endfor %}
{% if has_tail %}
    SET LR13 LR3 ; INC LR3 1 ; SUB LR2 LR0 CR1 ;
    LD.MULT R0 LR13 {{ cr.a }} ;;                 # a[i, {{ chunks - 1 }}] -> R0 (LR13, post-SET: LR3)
tloopt{{ tt }}:
    MULT.RC.VE LR0 LR2 0 LR0 CR15.L CR14.L ;
    ACC.ADD ;
    ADD LR1 LR1 {{ cr.wtiles }} ;
    LD.MULT.CYCLIC LR1 {{ cr.w }} LR0 ;
    INC LR2 1 ;
    BLT.S LR2 {{ cr.lanes_tail_m2 }} tloopt{{ tt }} ;;   # stops at k - 128 * (chunks - 1) inputs
{% endif %}
{% if bias %}
    MULT.VE LR5 CR1 0 LR0 CR15.L CR14.L ;         # b x 1.0, element-wise
    ACC.ADD ;                                     # onto the tile's accumulators
{% endif %}
    ACTIVATE.QUANTIZE identity {% if tt == ytiles - 1 %}CR15.H{% else %}CR15.L{% endif %} CR14.L {{ cr.y }} LR14 ;
    DEC LR10 1 ;
    BGE.S LR10 CR0 row{{ tt }} ;;                 # the next token of this tile
    ADD LR7 LR7 CR1 ; ADD LR4 LR4 CR1 ; ADD LR12 LR12 CR1 ;;   # the tile pointers ride on
{% endfor %}
end:
    HALT ;;
