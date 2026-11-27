{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set cb = (s0_cin + 127) // 128 %}
{% macro tap(y, x) %}
    BLT.S LR11 CR0 skip_{{y}}_{{x}} ;;
    BGE.S LR11 {{cr.input_hw}}.L skip_{{y}}_{{x}} ;;
    SET LR12 LR9 ;;
{% if x %}    INC LR12 {{x * cb}} ;; {% endif %}
{% for c in range(cb) %}
    LD.MULT R0 LR12 {{cr.in0}} ; SET LR14 CR0 ; SET LR13 CR0 ;;
    DEC LR14 1 ; INC LR13 {{ [128, s0_cin - c * 128] | min - 2 if [128, s0_cin - c * 128] | min > 1 else 0 }} ;;
    LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
{% if [128, s0_cin - c * 128] | min > 1 %}
channels_{{y}}_{{x}}_{{c}}:
    MULT.RC.VE LR0 LR14 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR14 1 ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
    MULT.RC.VE LR0 LR14 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
    MULT.RC.VE LR0 LR14 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR5 1 ; DEC LR13 1 ; LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ; BLT.S CR0 LR13 channels_{{y}}_{{x}}_{{c}} ;;
{% endif %}
    MULT.RC.VE LR0 LR14 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR14 1 ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
    MULT.RC.VE LR0 LR14 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
    MULT.RC.VE LR0 LR14 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR5 1 ;;
{% if c + 1 < cb %}    INC LR12 1 ;; {% endif %}
{% endfor %}
    B end_{{y}}_{{x}} ;;
skip_{{y}}_{{x}}:
    ADD LR5 LR5 {{cr.skip_x}} ;;
end_{{y}}_{{x}}:
{% if x + 1 < s0_kw %}    INC LR11 1 ;; {% endif %}
{% endmacro %}
{% macro save_pair(mask) %}
    ACTIVATE.QUANTIZE identity {{mask}} {{qo}} {{cr.tmp}} LR3 ; ADD LR12 LR3 LR10 ;;
    LD.MULT R0 LR3 {{cr.tmp}} ;;
    MULT.VE LR0 CR1 0 LR0 {{ds}} {{qo}} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{mask}} {{qo}} {{cr.tmp}} LR12 ;;
    LD.MULT R0 LR12 {{cr.tmp}} ;;
    ADD LR12 LR12 LR10 ;;
    MULT.VE LR0 CR1 0 LR0 {{ds}} {{qo}} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{mask}} {{qo}} {{cr.tmp}} LR12 ;;
{% endmacro %}
{% macro tap_row(y) %}
    BLT.S LR8 CR0 skip_y_{{y}} ;;
    BGE.S LR8 {{cr.input_hw}}.H skip_y_{{y}} ;;
    SET LR11 LR2 ;;
{% for x in range(s0_kw) %}{{tap(y,x)}}{% endfor %}
    B end_y_{{y}} ;;
skip_y_{{y}}:
    ADD LR5 LR5 {{cr.skip_y}} ;;
end_y_{{y}}:
{% if y + 1 < s0_kh %}    INC LR8 1 ; INC LR9 {{in0_d3 * cb}} ;; {% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR6 CR0 ; SET LR15 CR0 ;;
    INC LR15 {{ (out0_d1 + 127) // 128 }} ;;
{% if s0_padding %}    DEC LR1 {{s0_padding}} ; DEC LR6 {{s0_padding * in0_d3 * cb}} ;; {% endif %}
oy:
    SET LR2 CR0 ; SET LR7 LR6 ;;
{% if s0_padding %}    DEC LR2 {{s0_padding}} ; DEC LR7 {{s0_padding * cb}} ;; {% endif %}
ox:
    SET LR4 CR0 ; SET LR5 CR0 ;;
block:
    LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ; SET LR8 LR1 ; SET LR9 LR7 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR5 1 ;;
{% for y in range(s0_kh) %}{{tap_row(y)}}{% endfor %}
    LD.MULT.CYCLIC LR3 {{cr.in1}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{cr.qf_in1}}.L ; ACC.ADD ; INC LR4 1 ;;
    BLT.S LR4 LR15 full_store ;;
    {{save_pair(cr.tail ~ '.L')}}
    INC LR3 1 ; B next_pixel ;;
full_store:
    {{save_pair(ds)}}
    INC LR3 1 ; B block ;;
next_pixel:
    INC LR2 {{s0_stride}} ; INC LR7 {{s0_stride * cb}} ;;
    BLT.S LR2 {{cr.ends}}.L ox ;;
    INC LR1 {{s0_stride}} ; INC LR6 {{s0_stride * in0_d3 * cb}} ;;
    BLT.S LR1 {{cr.ends}}.H oy ;;
    SET LR14 LR10 ;;
    ADD LR15 LR14 LR14 ;;
    ADD LR15 LR15 LR14 ;;
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    SET LR6 CR0 ; SET LR10 CR0 ;;
{% for b in range((out0_d1 + 127) // 128) %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR6 CR0 ;;
channel_{{b}}:
    SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR11 {{b}} ; INC LR12 {{(out0_d2 * out0_d3 + 127) // 128}} ;;
chunk_{{b}}:
    SET LR13 CR0 ;;
phase_{{b}}:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    SET LR7 CR0 ; SET LR4 LR11 ; SET LR8 CR0 ;;
    BNE LR13 CR0 residual_{{b}} ;;
    B phase_address_{{b}} ;;
residual_{{b}}:
    ADD LR4 LR4 LR14 ;;
    BNE LR13 CR1 phase_address_{{b}} ;;
    ADD LR4 LR4 LR14 ;;
phase_address_{{b}}:
    INC LR8 128 ;;
    SET LR9 LR12 ;;
    DEC LR9 1 ;;
    BNE LR9 CR0 count_ready_{{b}} ;;
    SET LR8 CR0 ;;
    INC LR8 {{ (out0_d2 * out0_d3 - 1) % 128 + 1 }} ;;
count_ready_{{b}}:
    MULT.VE LR10 CR0 0 LR10 {{ds}} {{qo}} ; ACC.ADD.FIRST ;;
gather_{{b}}:
    LD.MULT R0 LR4 {{cr.tmp}} ;;
    MULT.VE LR10 CR1 0 LR10 {{ds}} {{qo}} ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR4 {{(out0_d1 + 127) // 128}} ; INC LR7 1 ;;
    ADDBI LRD2 1 ; BLT.S LR7 LR8 gather_{{b}} ;;
    BNE LR13 CR0 add_high_{{b}} ;;
    BEQ LR9 CR0 high_tail_{{b}} ;;
    ACTIVATE.QUANTIZE identity {{ds}} {{qo}} {{cr.out0}} LR5 ;;
    B high_done_{{b}} ;;
high_tail_{{b}}:
    ACTIVATE.QUANTIZE identity {{cr.full}}.H {{qo}} {{cr.out0}} LR5 ;;
high_done_{{b}}:
    LD.MULT R0 LR5 {{cr.out0}} ; ADD LR4 LR15 LR5 ;;
    MULT.VE LR10 CR1 0 LR10 {{ds}} {{qo}} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ds}} {{qo}} {{cr.tmp}} LR4 ;;
    INC LR13 1 ; B phase_{{b}} ;;
add_high_{{b}}:
    ADD LR4 LR15 LR5 ;;
    LD.MULT R0 LR4 {{cr.tmp}} ;;
    MULT.VE LR10 CR1 0 LR10 {{ds}} {{qo}} ; ACC.ADD ;;
    BNE LR13 CR1 final_add_{{b}} ;;
    ACTIVATE.QUANTIZE identity {{ds}} {{qo}} {{cr.tmp}} LR4 ;;
    INC LR13 1 ; B phase_{{b}} ;;
final_add_{{b}}:
    LD.MULT R0 LR5 {{cr.out0}} ;;
    MULT.VE LR10 CR1 0 LR10 {{ds}} {{qo}} ; ACC.ADD ;;
    BEQ LR9 CR0 final_tail_{{b}} ;;
    ACTIVATE.QUANTIZE {{act_out0}} {{ds}} {{qo}} {{cr.out0}} LR5 ;;
    B final_done_{{b}} ;;
final_tail_{{b}}:
    ACTIVATE.QUANTIZE {{act_out0}} {{cr.full}}.H {{qo}} {{cr.out0}} LR5 ;;
final_done_{{b}}:
    INC LR5 1 ;;
{% for i in range((out0_d1 + 127) // 128) %}    INC LR11 128 ;;
{% endfor %}
    DEC LR12 1 ;;
    BNE LR12 CR0 chunk_{{b}} ;;
    ADDBI LRD0 1 ; INC LR6 1 ;;
    SET LR9 CR0 ;;
    INC LR9 {{ [128, out0_d1 - b * 128] | min }} ;;
    BLT.S LR6 LR9 channel_{{b}} ;;
{% endfor %}
    HALT ;;
