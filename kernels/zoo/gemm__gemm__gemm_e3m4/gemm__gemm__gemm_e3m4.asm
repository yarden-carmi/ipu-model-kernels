{%- macro stage(sfx, incr, wcr, outcr, kreg, nbreg, instride, biasbase, dobias) -%}
    SET LR11 CR0 ;;
    SET LR5 CR0 ;;
    SET LR7 CR0 ;;
    SET LR12 {{ biasbase }} ;;
{{ sfx }}_m:
    SET LR6 CR0 ;;
{{ sfx }}_n:
    SET LR4 LR6 ;;
    SUB LR4 LR4 {{ nbreg }} ;;
    SET LR8 LR11 ;;
    SUB LR8 LR8 CR1 ;;
    SET LR3 CR0 ;;
    SUB LR3 LR3 CR1 ;;
    LD.MULT.CYCLIC LR6 {{ wcr }} LR2 ;;
    MULT.RC.VE LR2 CR0 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR9 CR0 ;;
{{ sfx }}_kb:
    LD.MULT R0 LR8 {{ incr }} ; INC LR8 1 ;;
    SET LR3 CR0 ;;
    SUB LR3 LR3 CR1 ;;
    LD.MULT.CYCLIC LR4 {{ wcr }} LR2 ; ADD LR4 LR4 {{ nbreg }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
    LD.MULT.CYCLIC LR4 {{ wcr }} LR2 ; ADD LR4 LR4 {{ nbreg }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
    LD.MULT.CYCLIC LR4 {{ wcr }} LR2 ; ADD LR4 LR4 {{ nbreg }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
    LD.MULT.CYCLIC LR4 {{ wcr }} LR2 ; ADD LR4 LR4 {{ nbreg }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% for i in range(124) %}
    MULT.RC.VE LR2 LR3 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ wcr }} LR2 ; ADD LR4 LR4 {{ nbreg }} ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(4) %}
    MULT.RC.VE LR2 LR3 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
    INC LR9 1 ;;
    BLT.S LR9 {{ kreg }} {{ sfx }}_kb ;;
{% if dobias %}
    ADD LR10 LR6 LR12 ;;
    LD.MULT.CYCLIC LR10 {{ cr.biases }} LR2 ;;
    MULT.RC.VE LR2 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE identity {{ cr.qf }}.H {{ cr.qf }}.L {{ outcr }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ nbreg }} {{ sfx }}_n ;;
    ADD LR11 LR11 {{ instride }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.s0_m }} {{ sfx }}_m ;;
{%- endmacro -%}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
{{ stage("s0", cr.in0, cr.w0, cr.out0, cr.K0, cr.NB0, cr.K0, "CR0", s0_bias) }}
{{ stage("s1", cr.out0, cr.w1, cr.out1, cr.NB0, cr.NB1, cr.NB0, cr.NB0, s1_bias) }}
{{ stage("s2", cr.out1, cr.w2, cr.out2, cr.NB1, "LR13", cr.NB1, "LR14", s2_bias) }}
    HALT ;;
