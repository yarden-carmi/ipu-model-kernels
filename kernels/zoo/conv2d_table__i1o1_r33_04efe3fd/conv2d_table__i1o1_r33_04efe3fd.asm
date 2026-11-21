{% set nbi = (cin + 127) // 128 %}
{% set nbo = cout // 128 %}
    SET LR0 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
{% if i < 4 %}
    INC LR0 1 ;;
{% endif %}
{% endfor %}
    SET LR0 CR0 ;;
    SET LR4 CR0 ;;
    SET LR6 CR0 ;;
    SET LR7 CR0 ;;
{% for block in range(nbi) %}
    ADD LR7 LR7 {{ cr.w }} ;;
    INC LR7 {{ 2 * padding }} ;;
{% endfor %}
clear_pad:
    MULT.VE LR0 CR0 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_pad }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf_pad }}.L {{ cr.pad }} LR4 ;;
    INC LR4 1 ;;
    BLT.S LR4 LR7 clear_pad ;;
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR4 CR0 ;;
    INC LR4 {{ padding * nbi }} ;;
    SET LR6 CR0 ;;
copy:
{% for ib in range(nbi) %}
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf_pad }}.L {{ cr.pad }} LR4 ;;
    INC LR2 1 ; INC LR4 1 ;;
{% endfor %}
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.w }} copy ;;
    SET LR3 CR0 ;;
    SET LR11 CR0 ;;
    SET LR12 CR0 ;;
oy:
    SET LR2 LR3 ;;
    SET LR10 CR0 ;;
ox:
    SET LR15 CR0 ;;
ob:
    LD.MULT.CYCLIC LR15 {{ cr.bias_vec }} LR0 ;;
    SET LR8 LR15 ;;
    MULT.RC.VE LR0 {{ 'CR1' if bias else 'CR0' }} 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_bias_vec }}.L ; ACC.ADD.FIRST ;;
    SET LR5 LR2 ;;
    DEC LR5 {{ padding * nbi }} ;;
{% for tap in range(kw) %}
    BLT.S LR5 CR0 skip_{{tap}} ;;
    SET LR7 CR0 ;;
{% for ib in range(nbi) %}
    ADD LR7 LR7 {{cr.w}} ;;
{% endfor %}
    BGE.S LR5 LR7 skip_{{tap}} ;;
{% for ib in range(nbi) %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    SET LR9 CR0 ;;
    SET LR7 CR0 ;;
    INC LR7 {{ [128, cin - ib * 128]|min }} ;;
ic_{{ tap }}_{{ ib }}:
{% set channels = [128, cin - ib * 128]|min %}
{% for u in range(8 if channels % 8 == 0 else 1) %}
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_weights }}.L ; ACC.ADD ;;
    INC LR8 {{ nbo }} ; INC LR9 1 ;;
{% endfor %}
    BLT.S LR9 LR7 ic_{{ tap }}_{{ ib }} ;;
    INC LR5 1 ;;
{% endfor %}
    BEQ CR0 CR0 next_{{tap}} ;;
skip_{{tap}}:
{% for skip in range(0, cin * nbo, 255) %}
    INC LR8 {{ [255, cin * nbo - skip]|min }} ;;
{% endfor %}
    INC LR5 {{ nbi }} ;;
next_{{tap}}:
{% endfor %}
    ACTIVATE.QUANTIZE generic {{ cr.dsfull }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ; INC LR15 1 ;;
    SET LR7 CR0 ;;
    INC LR7 {{ nbo }} ;;
    BLT.S LR15 LR7 ob ;;
    INC LR2 {{ stride * nbi }} ; INC LR10 1 ;;
    BLT.S LR10 {{ cr.wo }} ox ;;
    HALT ;;
