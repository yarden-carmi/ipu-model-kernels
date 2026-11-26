{% set chunks = (in0_d2 + 127) // 128 %}
{% set tiles = (out0_d1 + 127) // 128 %}
{% set prefix = n // 128 %}
{% set mixed = n % 128 %}
{% set gt = tiles - prefix %}
{% macro coeff() -%}
INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, first=false) -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro out(fn, ds, base, row) -%}
ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ base }} {{ row }}
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR5 CR0 ; SET LR10 CR0 ;;
{% for seg in range(5) %}
    {% if seg %}INC LR10 1 ; {% endif %}LD.LUT {{ seg }} {{ cr.lut }} LR10 ;;
{% endfor %}
gemm_pixel:
    {% if prefix %}INC LR5 {{ prefix }} ; {% endif %}SUB LR4 LR0 CR1 ; SET LR9 LR13 ;;
gemm_tile:
    SET LR6 LR2 ; SET LR7 LR3 ; SET LR8 LR14 ;;
    {{ coeff() }} ;;
    {{ mac('CR1', true) }} ; {{ coeff() }} ;;
    {{ mac('CR1') }} ; {{ coeff() }} ;;
tap:
    LD.MULT R0 LR6 {{ cr.in0 }} ;{% if chunks > 1 %} ADD LR10 LR6 CR1 ;{% endif %} ;;
{% if chunks > 1 %}
    LD.MULT R1 LR10 {{ cr.in0 }} ;;
{% endif %}
    {{ mac('LR7') }} ; {{ coeff() }} ; DEC LR8 1 ;;
    {{ mac('LR7') }} ; {{ coeff() }} ; BEQ LR8 CR0 gemm_store ;;
    ADD LR6 LR6 {{ cr.row_step }} ; ADD LR7 LR7 {{ cr.lane_step }} ;;
{% if m % in0_d2 %}
    BLT.S LR7 {{ cr.in0_d2 }} tap ;;
    SUB LR7 LR7 {{ cr.in0_d2 }} ; INC LR6 {{ chunks }} ;;
{% endif %}
    B tap ;;
gemm_store:
{% if mixed %}
    BEQ LR9 LR13 save_mixed ;;
{% endif %}
{% if gt > (1 if mixed else 0) %}
    BEQ LR9 CR1 gemm_last ;;
    {{ out('generic', cr.full_ds, cr.out0, 'LR5') }} ; B gemm_next ;;
gemm_last:
    {{ out('generic', cr.tail_ds, cr.out0, 'LR5') }} ; B gemm_next ;;
{% endif %}
{% if mixed %}
save_mixed:
    {{ out('generic', cr.tail_ds if gt == 1 else cr.full_ds, cr.mixed, 'LR1') }} ;;
{% endif %}
gemm_next:
    INC LR5 1 ; DEC LR9 1 ; DEC LR4 1 ; BNE LR9 CR1 gemm_tile ;;
    INC LR1 1 ; INC LR3 1 ;;
    BEQ LR1 LR15 skip_setup ;;
    BLT.S LR3 {{ cr.in0_d2 }} gemm_pixel ;;
    SET LR3 CR0 ; INC LR2 {{ chunks }} ; B gemm_pixel ;;

{# Gather the bypass channels directly into the output lanes. Only the
   boundary tile needs an already activated GEMM row. #}
{% macro gather(label, count, init, ds) %}
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR13 CR0 ;;
    INC LR13 {{ count }} ; {{ init }} ;;
{{ label }}:
    LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR0 ; DEC LR13 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD8 LRD6 7 ; ADD LR4 LR4 LR12 ;;
    ADDBI LRD6 1 ; BNE LR13 CR0 {{ label }} ;;
    {{ out('identity', ds, cr.out0, 'LR5') }} ;;
    INC LR5 1 ;;
{% endmacro %}
{% set clear = mac('CR0', true) %}
skip_setup:
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR5 CR0 ;;
skip_pixel:
    SET LR4 LR2 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR10 CR0 ;;
    ADDB LRD8 LR3 {% if prefix %}; INC LR10 {{ prefix }}{% endif %} ;;
{% if prefix %}
skip_full:
    {{ gather('gather_full', 128, clear, cr.full_ds) }}
    DEC LR10 1 ; BNE LR10 CR1 skip_full ;;
{% endif %}
{% if mixed %}
    LD.MULT.CYCLIC LR1 {{ cr.mixed }} LR0 ;;
    {% set restore = 'MULT.RC.VE LR0 CR1 0 LR0 ' ~ cr.full_ds ~ '.L ' ~ cr.qf_out0 ~ '.L ; ACC.ADD.FIRST' %}
    {{ gather('gather_mixed', mixed, restore, cr.tail_ds if gt == 1 else cr.full_ds) }}
{% endif %}
    INC LR1 1 ; INC LR3 1 {% if gt > (1 if mixed else 0) %}; INC LR5 {{ gt - (1 if mixed else 0) }}{% endif %} ;;
    BEQ LR1 LR15 end ;;
    BLT.S LR3 LR11 skip_pixel ;;
    SET LR3 CR0 ; INC LR2 1 ; B skip_pixel ;;
end:
    HALT ;;
