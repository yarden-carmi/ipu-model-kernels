{% macro gather_element(lane) %}
    MULT.EE {{ lane }} CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR6 {{ cr.scalar }}.L
{% endmacro %}

{% set single_slab = in0_d0 == 1 and out0_d0 == 1 %}

{% macro next_element(row_step, tag) %}
    ADD LR3 LR3 {{ row_step }} ; INC LR6 1 ; LD.MULT R0 LR3 {{ cr.in0 }} ; BLT.S LR6 LR10 gather_{{ tag }} ;;
{% endmacro %}

{% macro chunk(limit, ds, tag, n) %}
{% if single_slab %}
    // With one batch slab, every valid gather stays in the same slab.
    // Peel the last element so the pipelined loads never read past it.
    SET LR6 CR0 ; SET LR10 {{ limit }} ; LD.MULT R0 LR3 {{ cr.in0 }} ;;
{% if n > 1 %}
    DEC LR10 2 ;;
gather_{{ tag }}:
    {{ gather_element('LR14') }} ; SET LR14 LR5 ; INC.MODP2 LR5 LR13 7 ; BLT.S LR5 LR4 no_carry_{{ tag }} ;;
    {{ next_element('LR11', tag) }}
    B last_{{ tag }} ;;
no_carry_{{ tag }}:
    {{ next_element('LR12', tag) }}
{% endif %}
last_{{ tag }}:
    {{ gather_element('LR14') }} ; SET LR14 LR5 ; INC.MODP2 LR5 LR13 7 ; BLT.S LR5 LR4 last_no_carry_{{ tag }} ;;
    ADD LR3 LR3 LR11 ; B add_{{ tag }} ;;
last_no_carry_{{ tag }}:
    ADD LR3 LR3 LR12 ;;
add_{{ tag }}:
{% else %}
    SET LR6 CR0 ;;
gather_{{ tag }}:
    BLT.S LR4 {{ cr.span }} carry_{{ tag }} ;;
    SUB LR4 LR4 {{ cr.span }} ; ADD LR3 LR3 {{ cr.correction }} {% if in0_d1 * in0_d2 % 128 %}; DEC LR5 {{ in0_d1 * in0_d2 % 128 }}{% endif %} ;;
    BLT.S LR4 {{ cr.span }} carry_{{ tag }} ;;
    B gather_{{ tag }} ;;
carry_{{ tag }}:
{% if in0_d1 * in0_d2 % 128 %}
    BGE.S LR5 CR0 positive_{{ tag }} ;;
    INC LR5 128 ; DEC LR3 1 ;;
positive_{{ tag }}:
{% endif %}
    BLT.S LR5 LR2 load_{{ tag }} ;;
    DEC LR5 128 ; INC LR3 1 ;;
load_{{ tag }}:
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
    {{ gather_element('LR5') }} ; ADD LR4 LR4 {{ cr.step }} ; ADD LR3 LR3 LR12 ; SET LR14 LR5 ;;
    INC LR6 1 ; ADD LR5 LR14 LR13 ;;
    BLT.S LR6 {{ limit }} gather_{{ tag }} ;;
{% endif %}
    LD.MULT R1 LR1 {{ cr.in1 }} ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

// Read storage index a + A*b + A*B*c through the packed batch slabs.
    INC LR2 128 ;;
{% if single_slab %}
    SUB LR4 LR2 LR13 ; SET LR11 LR12 ;;
    INC LR11 1 ;;
{% endif %}
batch:
    SET LR7 CR0 ; SET LR8 {% if single_slab %}CR0{% else %}LR9{% endif %} ;;
position:
    SET LR3 CR0 ; {% if not single_slab %}SET LR4 LR8 ; {% endif %}SET LR5 LR8 ;;
origin:
    BLT.S LR5 LR2 chunks ;;
    DEC LR5 128 ; INC LR3 1 ; B origin ;;
chunks:
{% for b in range((out0_d2 - 1) // 128) %}
    {{ chunk('LR2', 'CR15.L', b, 128) }}
{% endfor %}
    {{ chunk('LR15', cr.tail ~ '.L', 'tail', (out0_d2 - 1) % 128 + 1) }}
    INC LR7 1 ; ADD LR8 LR8 {{ cr.out0_d0 }} ;;
    BLT.S LR7 {{ cr.out0_d1 }} position ;;
{% if not single_slab %}
    INC LR9 1 ;;
    BLT.S LR9 {{ cr.out0_d0 }} batch ;;
{% endif %}
    HALT ;;
