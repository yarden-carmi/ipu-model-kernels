{#- gemm.asm -- y = act(a @ w (+ b)), one parameterised program for every call.

    m tokens, k inputs, n output channels; nothing about the call is bigger than
    the tile, because every loop here is dynamic. Four nested loops, the three
    outer ones carried by LR counters and the innermost (the input loop inside a
    k chunk) the same, so the program is a fixed ~15 words whatever the shape:
    the whole of k is contracted inside the kernel and the whole of n and m are
    looped, so a layer -- 51866 channels, 5120 inputs, 4096 tokens -- is one
    launch and the host tiles only m if a call is too large for one.

    Layouts (kernel.toml has the CR map; every operand is a ROW number)
    - a, token-major: rows i * chunks + c hold token i's elements
      c * 128 .. c * 128 + 127, zero-padded past k by the packer.
    - w, *input-major*: row t * ytiles + tt holds input channel t's weights for
      the output channels tt * 128 .. tt * 128 + 127. Row k is padding: the
      input loop's last prefetch reads it and no multiply uses it. Lanes past n
      of every row are the packer's zeros, so a short last tile's extra lanes
      multiply zeros and its store (DS .L, all 128 lanes) writes zeros there.
    - b (when the call has one): its own region, ceil(n/128) rows -- row tt holds
      the biases of channels tt*128..tt*128+127, zero-padded past n, exactly the
      row the tile's store loads.
    - y: one row per token and tile, token-major: row i * ytiles + tt.

    Dataflow: the outer product, which is what makes one word one hundred
    twenty-eight useful MACs. Per token i, per tile tt and per input t, one word:
        MULT.RC.VE  R_CYCLIC[slot0] (= w[t, tt], 128 channels) x the scalar
                    R0[t mod 128] (= a[i, t]),
            MULT_RES[j] = w[t][tt * 128 + j] * a[i][t];
        ACC.ADD     adds the products into the tile's 128 R_ACC slots -- the
                    inputs of one output chain through the slot, so the whole of
                    k is contracted inside the kernel and no partial leaves XMEM.
    Each word prefetches the next input's w row into slot 0; MULT reads
    R_CYCLIC at cycle start (timing rule 2), so a word multiplies what the word
    before loaded, and a's row rides in the chunk's prologue word.
    - bias: the tile's b row is resident in R1 for the whole tile pass, so the
      store word is also the bias add: MULT.VE of R1 by the CR constant 1.0 and
      ACC.ADD, then the ACTIVATE.QUANTIZE in the same word.
    - the activation (relu; the sigmoid family is a later pass over a scratch
      copy of z): the AaQ function of the same name, on the store word's R_ACC,
      which already holds z = a @ w + b.
    - the store: DS .L, all 128 lanes, for every tile -- a short last tile's
      lanes past n hold zeros end to end (w's padding lanes, b's padding lanes),
      so its scale never sees a real lane's worth of junk and the lanes past n
      are written 0 for whatever kernel reads y next.
    - LR: LR0 0 (R_CYCLIC slot 0, the mask shift); LR1 w's row, reset per tile
      and stepped by ytiles per input; LR2 the input index inside a chunk (the
      inner loop's counter: -1 before the chunk, INC'd in the word, so the
      multiply sees 0, 1, ... and the branch -- which reads LRs as the word
      began -- the same value, so the bound is the chunk's input count minus
      one); LR3 a's row, free-running (one per chunk, never reset: token i's
      chunk c is row i * chunks + c); LR5 128 (R1's element offset in Ra);
      LR6 y's row, one per token (+ ytiles), reset per tile; LR7 the tile index
      (= w's row for input 0, = b's row, INC'd per tile); LR8 the input count
      of the token so far (INC'd per input; the chunk loop's BNE reads it
      against cbound = cfull * 128); LR10 the token counter (INC'd in the
      store word, its branch reads the pre-INC value, so the bound is m - 1);
      LR11 the tile counter (INC'd in the tile-advance word, bound
      ytiles - 1); LR12 the tile's y-row base; LR13 the value LR3 had when a's
      row was loaded (LOAD reads LRs forwarded, so the INC rides in the same
      word); LR14 the y row being stored.
    - Words: per token and tile, 2 + cfull * 130 + (tail ? tail + 1 : 0) + 1,
      plus a fixed prologue and per-tile prologue; one word per (token, tile,
      input) at 128 MACs a word.
-#}
{% set chunks = (k + 127) // 128 %}
{% set has_tail = (k % 128) != 0 %}
{% set cfull = k // 128 %}
{% set tail = k - 128 * cfull %}
{% set actfn = {"none": "identity", "relu": "relu"}[act] %}
    SET LR0 CR0 ; SET LR5 {{ cr.slot1 }} ;;            {#- 0; R1's element offset in Ra -#}
    SET LR3 CR0 ; SET LR10 CR0 ;;                      {#- a's row; the token counter -#}
    SET LR7 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;       {#- the tile index; tile counter; tile's y base -#}
    LD.MASK LR0 {{ cr.maskr }} ;;                      {#- every lane of every multiply active -#}
pass:
    SET LR3 CR0 ; SET LR6 LR12 ; SET LR10 CR0 ;{% if bias %} LD.MULT R1 LR7 {{ cr.b }} ;;{% else %} ;;{% endif %}
row:
    MULT.VE LR0 CR0 0 LR0 CR15.L CR14.L ;              {#- 0 x Ra: this tile's slots to zero -#}
    ACC.ADD.FIRST ;                                    {#- R_ACC := 0 (once per row) -#}
    SET LR8 CR0 ;;                                     {#- the chunk counter, per token -#}
    LD.MULT.CYCLIC LR1 {{ cr.w }} LR0 ;                {#- w[0, tt] -> slot 0 (LR1 post-SET) -#}
    SET LR1 LR7 ; SET LR14 LR6 ; ADD LR6 LR6 {{ cr.stride }} ;;
{% if cfull >= 1 %}
chunk_loop:
    SET LR13 LR3 ; INC LR3 1 ; SUB LR2 LR0 CR1 ;       {#- the input counter: -1, so it sees 0, 1, ... -#}
    LD.MULT R0 LR13 {{ cr.a }} ;;                      {#- a[i, c] -> R0 (LR13, post-SET: LR3) -#}
tloop:
    MULT.RC.VE LR0 LR2 0 LR0 CR15.L CR14.L ;           {#- w[t, tt] x a[i, t]: 128 channels at once -#}
    ACC.ADD ;                                          {#- into the tile's 128 accumulators -#}
    ADD LR1 LR1 {{ cr.stride }} ;                      {#- the w row the NEXT word multiplies -#}
    LD.MULT.CYCLIC LR1 {{ cr.w }} LR0 ;
    INC LR2 1 ; INC LR8 1 ;
    BLT.S LR2 {{ cr.lanes_full }} tloop ;;             {#- a full chunk: 128 inputs -#}
{% if cfull >= 2 %}
    BNE LR8 {{ cr.cbound }} chunk_loop ;;              {#- the next full chunk of this token -#}
{% endif %}
chunk_done:
{% endif %}
{% if has_tail %}
    SET LR13 LR3 ; INC LR3 1 ; SUB LR2 LR0 CR1 ;
    LD.MULT R0 LR13 {{ cr.a }} ;;                      {#- a[i, {{ chunks - 1 }}] -> R0 -#}
ttloop:
    MULT.RC.VE LR0 LR2 0 LR0 CR15.L CR14.L ;
    ACC.ADD ;
    ADD LR1 LR1 {{ cr.stride }} ;
    LD.MULT.CYCLIC LR1 {{ cr.w }} LR0 ;
    INC LR2 1 ;
    BLT.S LR2 {{ cr.lanes_tail }} ttloop ;;            {#- stops at the chunk's last input -#}
{% endif %}
{% if bias %}
    MULT.VE LR5 CR1 0 LR0 CR15.L CR14.L ;              {#- b x 1.0, element-wise -#}
    ACC.ADD ;                                          {#- onto the tile's accumulators -#}
{% endif %}
    ACTIVATE.QUANTIZE {{ actfn }} CR15.L CR14.L {{ cr.y }} LR14 ;
    INC LR10 1 ;
    BLT.S LR10 {{ cr.mbound }} row ;;                  {#- the next token of this tile -#}
    ADD LR7 LR7 CR1 ; ADD LR12 LR12 CR1 ; INC LR11 1 ; {#- the tile pointers ride on -#}
    BLT.S LR11 {{ cr.ytiles_m1 }} pass ;;              {#- the next output tile -#}
end:
    HALT ;;
