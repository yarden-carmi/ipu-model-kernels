{%- macro stage(sfx, incr, wcr, outcr, kreg, nbreg, instride, biasbase, dobias) -%}
    SET LR11 CR0 ;;
    SET LR5 CR0 ;;
    SET LR7 CR0 ;;
    SET LR12 {{ biasbase }} ;;
{{ sfx }}_m:
    SET LR6 CR0 ;;
{{ sfx }}_n:
{% if sfx == 's2' %}
    SET LR10 CR0 ;;
    SET LR1 CR0 ;;
{% for block in range((s0_m + 127) // 128) %}
    SET LR3 CR0 ;;
{% for j in range(block + 1) %}
    INC LR3 128 ;;
{% endfor %}
    BLT.S LR5 LR3 s2_found_{{ block }} ;;
{% endfor %}
{% for block in range((s0_m + 127) // 128) %}
s2_found_{{ block }}:
    SET LR10 CR0 ;;
    INC LR10 {{ block }} ;;
    SET LR1 LR5 ;;
    SET LR3 CR0 ;;
{% for j in range(block) %}
    INC LR3 128 ;;
{% endfor %}
    SUB LR1 LR1 LR3 ;;
    BEQ CR0 CR0 s2_found ;;
{% endfor %}
s2_found:
{% endif %}
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
{% if sfx != 's2' %}
    LD.MULT R0 LR8 {{ incr }} ; INC LR8 1 ;;
{% endif %}
    SET LR3 CR0 ;;
    SUB LR3 LR3 CR1 ;;
    LD.MULT.CYCLIC LR4 {{ wcr }} LR2 ; ADD LR4 LR4 {{ nbreg }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
    LD.MULT.CYCLIC LR4 {{ wcr }} LR2 ; ADD LR4 LR4 {{ nbreg }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
    LD.MULT.CYCLIC LR4 {{ wcr }} LR2 ; ADD LR4 LR4 {{ nbreg }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
    LD.MULT.CYCLIC LR4 {{ wcr }} LR2 ; ADD LR4 LR4 {{ nbreg }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% for i in range(124) %}
{% if sfx == 's2' %}
    LD.MULT R0 LR10 {{ incr }} ;;
    INC LR10 {{ (s0_m + 127) // 128 }} ;;
{% endif %}
    MULT.RC.VE LR2 {{ 'LR1' if sfx == 's2' else 'LR3' }} 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ wcr }} LR2 ; ADD LR4 LR4 {{ nbreg }} ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(4) %}
{% if sfx == 's2' %}
    LD.MULT R0 LR10 {{ incr }} ;;
    INC LR10 {{ (s0_m + 127) // 128 }} ;;
{% endif %}
    MULT.RC.VE LR2 {{ 'LR1' if sfx == 's2' else 'LR3' }} 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
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
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
{{ stage("s0", cr.in0, cr.w0, cr.out0, "LR15", cr.NB0, "LR15", "CR0", s0_bias) }}
    SET LR7 CR0 ;;
    SET LR6 CR0 ;;
    SET LR4 CR0 ;;
s1_n:
{% for block in range((s0_m + 127) // 128) %}
    SET LR1 CR0 ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR8 CR0 ;;
{% for j in range(block * (s0_n // 128)) %}
    INC LR8 128 ;;
{% endfor %}
s1_m_{{block}}:
    SET LR9 CR0 ;;
    SET LR10 LR4 ;;
s1_k_{{block}}:
    LD.MULT R0 LR10 {{ cr.w1 }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.out0 }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; AGG.SUM LR1 {{ cr.qf }}.H ;;
    INC LR10 1 ; INC LR8 1 ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.NB0 }} s1_k_{{block}} ;;
    INC LR1 1 ;;
    SET LR3 CR0 ;;
    INC LR3 {{ [128, s0_m - block * 128]|min }} ;;
    BLT.S LR1 LR3 s1_m_{{block}} ;;
{% if s1_bias %}
    SET LR10 CR0 ;;
    INC LR10 {{ s0_n // 128 }} ;;
    SET LR9 LR6 ; SET LR3 CR0 ;;
s1_bias_{{block}}:
    BLT.S LR9 {{ cr.c128 }} s1_bias_ready_{{block}} ;;
    SUB LR9 LR9 {{ cr.c128 }} ; INC LR10 1 ;;
    BEQ CR0 CR0 s1_bias_{{block}} ;;
s1_bias_ready_{{block}}:
    LD.MULT R0 LR10 {{ cr.biases }} ;;
    MULT.EE LR9 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE identity {{ cr.tail ~ '.L' if block == (s0_m + 127) // 128 - 1 else cr.qf ~ '.H' }} {{ cr.qf }}.L {{ cr.out1 }} LR7 ;;
    INC LR7 1 ;;
{% endfor %}
    ADD LR4 LR4 {{ cr.NB0 }} ; INC LR6 1 ;;
    SET LR3 CR0 ;;
{% for j in range(s1_n // 128) %}
    INC LR3 128 ;;
{% endfor %}
    BLT.S LR6 LR3 s1_n ;;
{{ stage("s2", cr.out1, cr.w2, cr.out2, cr.NB1, "LR13", cr.NB1, "LR14", s2_bias) }}
    HALT ;;
