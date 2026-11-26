{% set chunks = (in0_d2 + 127) // 128 %}
{% set step = s0_m // 128 %}
{% set rem = s0_m % 128 %}
{% set full = cr.full ~ '.L' %}
{% set q = cr.qf_in0 ~ '.L' %}
    INC LR1 128 ; INC LR2 128 ; INC LR3 128 ;;
    ADD LR2 LR2 LR1 ; ADD LR3 LR3 LR1 ; SET LR8 {{cr.bias_start}} ;;
    ADD LR3 LR3 LR1 ; DEC LR6 1 ; DEC LR4 1 ;;
    DEC LR7 1 ; DEC LR15 1 ;;
batch:
    INC LR15 1 ; SET LR12 CR0 ; SET LR13 {{cr.out0_d1}} ;;
    SET LR11 LR15 ;;
token:
    SET LR9 LR12 ; SET LR10 LR11 ; SET LR14 {{cr.s0_n}} ;;
    SUB LR5 LR0 CR1 ;;
{% for i in range(chunks) %}
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{cr.in0}} LR{{i}} ;;
{% endfor %}
channel:
    BGE.S LR7 CR0 accumulate ;;
    LD.MULT R1 LR8 {{cr.w}} ;;
    MULT.VE LR1 CR1 0 LR0 {{full}} {{q}} ; ACC.ADD.FIRST ; INC LR8 1 ;;
    BLT.S LR8 {{cr.bias_end}} accumulate ;;
    SET LR8 {{cr.bias_start}} ;;
accumulate:
    INC LR7 1 ; INC LR5 1 ; LD.MULT R{{chunks % 2}} LR5 {{cr.w}} ;;
{% for i in range(chunks) %}
    {% set ra = (chunks - i) % 2 %}
    MULT.RC.VV LR{{i}} R{{ra}} 0 LR0 {{full}} {{q}} ; AGG.SUM LR7 {{full}}
    {% if i + 1 < chunks %}; INC LR5 1 ; LD.MULT R{{1-ra}} LR5 {{cr.w}}{% else %}; LD.MULT R0 LR9 {{cr.in1}}{% endif %} ;;
{% endfor %}
    MULT.EE LR10 CR1 0 LR0 {{full}} {{cr.qf_in1}}.L ; AGG.SUM LR7 {{cr.one}}.L ; DEC LR14 1 ;;
    INC LR7 1 {% if step %}; INC LR9 {{step}}{% endif %}{% if rem %}; INC LR10 {{rem}}{% endif %} ;;
{% if rem %}
    BLT.S LR10 LR1 residual_ready ;;
    DEC LR10 128 ; INC LR9 1 ;;
residual_ready:
{% endif %}
    BLT.S LR7 LR1 partial ;;
    INC LR6 1 ; ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{full}} {{cr.qf_out0}}.L {{cr.out0}} LR6 ; SET LR7 CR0 ;;
partial:
    DEC LR7 1 ; BNE LR14 CR0 channel ;;
    DEC LR13 1 ; INC LR11 {{out0_d0}} ;;
    BEQ LR13 CR0 next_batch ;;
    BLT.S LR11 LR1 token ;;
    DEC LR11 128 ; INC LR12 1 ; B token ;;
next_batch:
    ADD LR9 LR15 CR1 ;;
    BLT.S LR9 {{cr.out0_d0}} batch ;;
    HALT ;;
