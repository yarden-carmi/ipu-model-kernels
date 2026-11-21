{# Input view is flat NCHW; each packed d1 group ends at a row boundary. #}
{% macro store(fn, ds, base, ptr) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ base }} {{ ptr }} ;;
{% endmacro %}
{% macro copy_vec(op) %}
    LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; {{ op }} ; INC LR1 {{ (in1_d1 + 127) // 128 }} ;;
{% endmacro %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR13 CR0 ;;
    SET LR14 CR0 ; SET LR15 CR0 ; SET LR12 CR0 ;;
    INC LR13 128 ; INC LR15 {{ in1_d1 // 128 }} ;;
    INC LR12 {{ (out0_d1 - 1) // 128 }} ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR3 ;;
    INC LR3 1 ;;
{% endfor %}
{% if in1_d1 >= 128 %}
copy_block:
    SET LR3 CR0 ; SET LR1 LR14 ; SET LR2 LR14 ;;
copy_row:
    {{ copy_vec('ACC.ADD.FIRST') }}
    {{ store('identity', cr.full, cr.out0, 'LR2') }}
    INC LR2 {{ (out0_d1 + 127) // 128 }} ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.m }} copy_row ;;
    INC LR14 1 ;;
    BLT.S LR14 LR15 copy_block ;;
{% endif %}
compute_block:
    SET LR3 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR1 LR14 ; SET LR2 LR14 ;;
pixel:
    SET LR7 LR4 ; SET LR8 LR5 ; SET LR9 LR6 ;;
    SET LR10 CR0 ;;
    INC LR10 {{ k }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR0 ;;
    INC LR7 1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR13 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR7 1 ;;
    MULT.RC.VE LR13 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
channel:
    LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR0 ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR7 1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR13 ; INC LR8 {{ m // 128 }} ;;
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR7 1 ;;
    MULT.RC.VE LR13 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR10 1 ;;
{% if m % 128 %}
    INC LR9 {{ m % 128 }} ;;
    BLT.S LR9 LR13 channel_done ;;
    SUB LR9 LR9 LR13 ; INC LR8 1 ;;
channel_done:
{% endif %}
    BNE LR10 CR0 channel ;;
{% if in1_d1 % 128 %}
    BNE LR14 LR15 computed_only ;;
    # The shared boundary row contains both untouched and activated channels.
    {{ store(act, cr.full, cr.activated, 'LR0') }}
    LD.MULT.CYCLIC LR0 {{ cr.activated }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR1 {{ cr.in1 }} ; SET LR10 {{ cr.map_lo }} ; SET LR11 {{ cr.map_hi }} ;;
    INC LR1 {{ (in1_d1 + 127) // 128 }} ; SET LR8 CR0 ; SET LR9 CR0 ;;
{% set overlap = in1_d1 % 128 %}
{% if overlap >= 8 %}
    INC LR8 {{ overlap // 8 }} ;;
merge_octet:
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD10 LRD10 0 ; DEC LR8 1 ;;
    ADDBI LRD10 8 ; BNE LR8 CR0 merge_octet ;;
{% endif %}
{% if overlap % 8 %}
    DEC LR9 {{ 8 - overlap % 8 }} ;;
    ADDBI LRD10 LR9 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD10 LRD10 {{ 8 - overlap % 8 }} ;;
{% endif %}
    BEQ LR14 LR12 mixed_tail ;;
    {{ store('identity', cr.full, cr.out0, 'LR2') }}
    B pixel_done ;;
mixed_tail:
    {{ store('identity', cr.tail, cr.out0, 'LR2') }}
    B pixel_done ;;
computed_only:
{% endif %}
    BEQ LR14 LR12 compute_tail ;;
    {{ store(act, cr.full, cr.out0, 'LR2') }}
    B pixel_done ;;
compute_tail:
    {{ store(act, cr.tail, cr.out0, 'LR2') }}
pixel_done:
    INC LR2 {{ (out0_d1 + 127) // 128 }} ; INC LR3 1 ; INC LR6 1 ;;
    BLT.S LR6 LR13 pixel_next ;;
    SET LR6 CR0 ; INC LR5 1 ;;
pixel_next:
    BLT.S LR3 {{ cr.m }} pixel ;;
    SET LR4 LR7 ; INC LR14 1 ;;
    BLE.S LR14 LR12 compute_block ;;
    HALT ;;
