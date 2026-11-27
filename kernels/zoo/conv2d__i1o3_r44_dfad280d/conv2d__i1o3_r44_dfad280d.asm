{% set chunks = (in0_d1 + 127) // 128 %}
{% macro tap(y, x) %}
    SET LR10 LR5 ; SET LR11 LR6 ; SET LR12 LR4 ;;
    {% if y == 0 %} DEC LR10 1 ;; {% elif y == 2 %} INC LR10 1 ;; {% endif %}
    {% if x == 0 %} DEC LR11 1 ;; {% elif x == 2 %} INC LR11 1 ;; {% endif %}
    {% if y == 0 %} BLT.S LR10 CR0 skip_{{y}}_{{x}} {% if x == 0 %}; INC LR9 1 {% endif %} ;; {% elif y == 2 %} BGE.S LR10 {{ cr.skip_y }} skip_{{y}}_{{x}} ;; {% endif %}
    {% if x == 0 %} BLT.S LR11 CR0 skip_{{y}}_{{x}} ;; {% elif x == 2 %} BGE.S LR11 {{ cr.input_hw }} skip_{{y}}_{{x}} ;; {% endif %}
    {% set delta = ((y - 1) * in0_d3 + x - 1) * chunks %}
    {% for i in range(0, delta|abs, 255) %}
    {{ 'INC' if delta > 0 else 'DEC' }} LR12 {{ [255, delta|abs - i]|min }} ;;
    {% endfor %}
    LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR15 ;;
    {% for c in range(chunks) %}
    LD.MULT R0 LR9 {{ cr.weights }} {% if c + 1 < chunks %}; INC LR12 1 {% endif %} ;;
    MULT.RC.VV LR15 R0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR7 {{ cr.full }}.L ; INC LR9 1 {% if c + 1 < chunks %}; LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR15 {% endif %} ;;
    {% endfor %}
    {% if y != 1 or x != 1 %} B end_{{y}}_{{x}} ;;
skip_{{y}}_{{x}}:
    INC LR9 {{ chunks }} ;;
end_{{y}}_{{x}}:
    {% endif %}
{% endmacro %}
    SET LR15 CR0 ; SET LR0 CR0 ; SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    SET LR14 CR0 ;;
    INC LR14 {{ [128, 2 * out0_d3] | min }} ;;
channel:
    SET LR3 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR4 CR0 ;;
row:
    LD.MULT.CYCLIC LR1 {{ cr.weights }} LR15 ; SET LR7 CR0 ;;
    MULT.RC.VE LR15 {{ 'CR1' if bias else 'CR0' }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
pixel:
    SET LR9 LR1 ;;
    {% for y in range(3) %}{% for x in range(3) %}{{tap(y,x)}}{% endfor %}{% endfor %}
    INC LR7 1 ; INC LR6 1 ; INC LR4 {{ chunks }} ;;
    BLT.S LR6 {{ cr.input_hw }} no_new_y ;;
    SET LR6 CR0 ; INC LR5 1 ;;
no_new_y:
    BLT.S LR7 LR14 pixel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.ends }} row ;;
    ADD LR1 LR1 {{ cr.plane }} ; INC LR0 1 ;;
    BLT.S LR0 {{ cr.out0_d1 }} channel ;;
    HALT ;;
