{#- binary_mul_col_e1m6: out0[i, j] = in0[i, j] * in1[j] (broadcast col), e1m6.

    in0 is [m, n] with dimension 1 along the 128 lanes, so each logical
    row spans `chunks = ceil(n / 128)` physical memory rows; physical row
    p of in0 holds in1 chunk c = p % chunks along the lanes. The chunk
    loop is unrolled in the template. For chunks <= 4 (n <= 512) every
    in1 chunk is loaded once into its own R_CYCLIC slot (element offsets
    0/128/256/384) before the row loop; for chunks = 5 (n = 576, 640
    elements > the 512-element ring) each chunk is reloaded into the
    ring every iteration, one load-slot word per word. Per chunk:
    LD.MULT in0 physical row p into R0, MULT.RC.VV multiplies it
    element-wise by the in1 chunk (slot at element offset c*128),
    ACC.ADD.FIRST puts the product in R_ACC, ACTIVATE.QUANTIZE identity
    stores it to out0 physical row LR0 (in0 and out0 share rows, written
    in place), then INC LR0 steps to the next physical row. The last
    chunk of each logical row has tail = n - (chunks-1)*128 valid lanes:
    it is masked in the multiplier (mask_shift 0) and stored with the DS
    half ds_tail so padding lanes are written zero; all other chunks use
    the full DS CR15.L.
-#}
{% set chunks = (n + 127) // 128 %}
{% set tailc = chunks - 1 %}
    SET LR0 CR0 ;;                 # physical row index p
    SET LR1 CR0 ;;                 # element offset 0 / mask_shift 0
    SET LR3 CR0 ;;                 # in1 row offset, chunk 0
{% for c in range(1, chunks) %}
    SET LR{{ 3 + c }} LR3 ;;
    INC LR{{ 3 + c }} {{ c }} ;;   # in1 row offset, chunk {{ c }}
{% endfor %}
    SET LR10 CR0 ;;                # cyclic slot index, chunk 0
    SET LR11 LR10 ;;
    INC LR11 128 ;;                # slot index, chunk 1
{% if chunks > 2 %}
    SET LR12 LR10 ;;
    INC LR12 128 ;;
    INC LR12 128 ;;                # slot index, chunk 2
{% endif %}
{% if chunks > 3 %}
    SET LR13 LR10 ;;
    INC LR13 128 ;;
    INC LR13 128 ;;
    INC LR13 128 ;;                # slot index, chunk 3
{% endif %}
{% if chunks <= 4 %}
{% for c in range(chunks) %}
    LD.MULT.CYCLIC LR{{ 3 + c }} {{ cr.in1 }} LR{{ 10 + c }} ;;
{% endfor %}
{% endif %}
row_loop:
{% for c in range(chunks) %}
{% set sidx = 10 + c if c < 4 else 10 %}
{% if chunks > 4 %}
    LD.MULT.CYCLIC LR{{ 3 + c }} {{ cr.in1 }} LR{{ sidx }} ;;
{% endif %}
    LD.MULT R0 LR0 {{ cr.in0 }} ;;
{% if c == tailc %}
    MULT.RC.VV LR{{ sidx }} R0 0 LR1 {{ cr.ds_tail }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds_tail }}.L {{ cr.qf }}.L {{ cr.out0 }} LR0 ;;
{% else %}
    MULT.RC.VV LR{{ sidx }} R0 0 LR1 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR0 ;;
{% endif %}
    INC LR0 1 ;;
{% endfor %}
    BLT.S LR0 {{ cr.phys }} row_loop ;;
    HALT ;;
