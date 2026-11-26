{% set act = act_out0 | default('identity') %}
{% set tail_ds = cr.tail ~ '.L' %}
{% set full_ds = 'CR15.L' %}
{% set q0 = cr.qf_in0 ~ '.L' %}
{% set q1 = cr.qf_in1 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set positions = cr.positions_blocks ~ '.L' %}
{% set blocks_cr = cr.positions_blocks ~ '.H' %}
{% set channels = cr.channels_phases ~ '.L' %}
{% set phases = cr.channels_phases ~ '.H' %}

{% macro add_row(ds) %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q0 }} ; ACC.ADD.FIRST ; INC LR4 1 ; SET LR5 LR1 ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ q1 }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR1 1 ;;
{% endmacro %}

{% macro finish(which, ds, zero='LR0') %}
{% if which == 'patch' %}
    // Preserve the gathered vector as a leading term and two residual terms.
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.parts }} LR11 ;;
    {% for i in range(2) %}
    LD.MULT R0 LR11 {{ cr.parts }} ;;
     INC LR11 1 ; MULT.VE {{ zero }} CR1 0 {{ zero }} {{ ds }} {{ qo }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.parts }} LR11 ;;
    {% endfor %}
    INC LR11 1 ;;
{% else %}
    {% for i in range(2, -1, -1) %}
    LD.MULT R0 LR11 {{ cr.parts }} ;;
    // The scalar words also decode as FP32. Cancel their FP32 gain error;
    // the correction scalar decodes to zero in NX8.
    {% for _ in range(6) %}
     MULT.VE {{ zero }} {{ cr.scale_correction }} 0 {{ zero }} {{ ds }} {{ qo }} ; ACC.SUB ;;
    {% endfor %}
     MULT.VE {{ zero }} {{ cr.scale_down }} 0 {{ zero }} {{ ds }} {{ qo }} ; ACC.ADD {% if i == 0 %}; ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR10 {% endif %};;
    {% if i %}DEC LR11 1 ;;{% endif %}
    {% endfor %}
    INC LR11 5 ; INC LR10 1 ;;
{% endif %}
{% endmacro %}

{% macro gather_eight(which, tensor, qf, step, phase_step) %}
    SET LR6 CR0 ; SET LR7 {{ phases }} ; SET LR10 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ;;
    {% if which != 'patch' %}INC LR11 2 ;;{% endif %}
{{ which }}_plane:
    SET LR13 CR0 ; SET LR5 LR6 ; SET LR4 LR6 ;;
    SET LR8 {{ positions }} ;;
    SET LR9 {{ channels }} ;;
{{ which }}_row:
    SET LR2 LR0 ; SET LR3 LR1 ; LD.MULT R0 LR5 {{ tensor }} ;;
{{ which }}_eight:
    // LR13 aligns the source group to lanes 0..7; the destination ramp
    // advances independently across packed output rows.
    MULT.VE LR13 {{ cr.scale_up if which == 'patch' else 'CR1' }} 0 LR12 {{ full_ds }} {{ qf }} ; ACC.RESHAPE LRD0 LRD2 0 ; DEC LR9 8 ;;
    ADDBI LRD2 8 ; INC LR13 8 ; BEQ LR9 CR0 {{ which }}_position ;;
    BEQ LR13 {{ cr.tail }}.H {{ which }}_block ;;
{{ which }}_continue:
    // After 16 groups, the highest destination byte reaches 135 and
    // sets LR3's sign bit. The next output row resets the ramp.
    BGE.S LR3 CR0 {{ which }}_eight ;;
    {{ finish(which, full_ds, 'LR12') }}
    B {{ which }}_row ;;
{{ which }}_block:
    INC LR5 1 ; SET LR13 CR0 ;;
    BLT.S LR3 CR0 {{ which }}_continue ;;
    LD.MULT R0 LR5 {{ tensor }} ; B {{ which }}_eight ;;
{{ which }}_position:
    DEC LR8 1 ;;
    BEQ LR8 CR0 {{ which }}_last ;;
    SET LR13 CR0 ; SET LR9 {{ channels }} ; ADD LR4 LR4 {{ step }} ;;
    SET LR5 LR4 ; BLT.S LR3 CR0 {{ which }}_continue ;;
    LD.MULT R0 LR5 {{ tensor }} ; B {{ which }}_eight ;;
{{ which }}_last:
    {{ finish(which, tail_ds, 'LR12') }}
    ADD LR6 LR6 {{ phase_step }} ; DEC LR7 1 ;;
    BNE LR7 CR0 {{ which }}_plane ;;
{% endmacro %}

{% macro gather(which, tensor, qf, step, phase_step) %}
    SET LR6 CR0 ; SET LR7 {{ phases }} ; SET LR10 CR0 ;;
    SET LR11 CR0 ;;
    {% if which != 'patch' %}INC LR11 2 ;;{% endif %}
{{ which }}_plane:
    SET LR1 CR0 ; SET LR4 LR6 ; SET LR5 LR6 ;;
    SET LR9 {{ channels }} ; SET LR8 {{ positions }} ;;
    DEC LR9 1 ;;
{{ which }}_row:
    // Prime the gather; the bottom of the loop loads the next element's row.
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR12 LR13 ; LD.MULT R0 LR5 {{ tensor }} ;;
{{ which }}_element:
    MULT.EE LR1 {{ cr.scale_up if which == 'patch' else 'CR1' }} 0 LR0 {{ full_ds }} {{ qf }} ; ACC.RESHAPE LRD0 LRD2 7 ; DEC LR12 1 ; BEQ LR9 CR0 {{ which }}_position ;;
    DEC LR9 1 ; INC.MODP2 LR1 CR1 7 ;;
    BNE LR1 CR0 {{ which }}_ready ;;
    INC LR5 1 ; B {{ which }}_ready ;;
{{ which }}_position:
    DEC LR8 1 ;;
    BEQ LR8 CR0 {{ which }}_last ;;
    SET LR9 {{ channels }} ; SET LR1 CR0 ; ADD LR4 LR4 {{ step }} ;;
    DEC LR9 1 ; SET LR5 LR4 ;;
{{ which }}_ready:
    ADDBI LRD2 1 ; LD.MULT R0 LR5 {{ tensor }} ; BNE LR12 CR0 {{ which }}_element ;;
    {{ finish(which, full_ds) }}
    B {{ which }}_row ;;
{{ which }}_last:
    {{ finish(which, tail_ds) }}
    ADD LR6 LR6 {{ phase_step }} ; DEC LR7 1 ;;
    BNE LR7 CR0 {{ which }}_plane ;;
{% endmacro %}

{% if out0_d2 <= 144 or out0_d1 == 1 %}
    SET LR0 CR0 ; SET LR1 CR0 ;;
    INC LR2 128 ; SET LR13 {{ phases }} ; SUB LR14 LR14 {{ blocks_cr }} ;;
position:
{% if out0_d2 <= 512 %}
    {% for _ in range((out0_d2 - 1) // 128) %}
        {{ add_row(full_ds) }}
    {% endfor %}
{% else %}
    SET LR3 {{ blocks_cr }} ;;
block:
    DEC LR3 1 ;;
    BEQ LR3 CR0 tail ;;
    {{ add_row(full_ds) }}
    B block ;;
tail:
{% endif %}
    {{ add_row(tail_ds) }}
    INC LR7 1 ; ADD LR4 LR4 LR14 ;;
    BLT.S LR7 {{ positions }} position ;;
    SET LR7 CR0 ; ADD LR6 LR6 {{ blocks_cr }} ; DEC LR13 1 ;;
    SET LR4 LR6 ; BNE LR13 CR0 position ;;
{% else %}
    {% if out0_d2 % 8 == 0 %}
    {{ gather_eight('patch', cr.in0, q0, 'LR14', blocks_cr) }}
    {{ gather_eight('other', cr.in1, q1, blocks_cr, 'LR15') }}
    {% else %}
    SET LR0 CR0 ;;
    INC LR13 128 ;;
    {{ gather('patch', cr.in0, q0, 'LR14', blocks_cr) }}
    {{ gather('other', cr.in1, q1, blocks_cr, 'LR15') }}
    {% endif %}
{% endif %}
    HALT ;;
