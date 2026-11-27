{% macro dot(prefetch) %}
    MULT.RC.VV LR3 R0 0 LR11 {{ cr.ds_main }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR9 {{ cr.ds_main }}.H ; INC LR9 1 ; ADD LR7 LR7 {{ cr.strides }}.H {% if prefetch %}; LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR11 ; DEC LR10 1 ; BNE LR10 CR1 {{ prefetch }}{% endif %} ;;
{% endmacro %}
{% macro output(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ; INC LR0 1 ;;
{% endmacro %}
{% macro rows(tag, rotate) %}
{{ tag }}_row:
{% if rotate %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR11 ; SET LR7 LR1 ; SET LR8 {{ cr.sizes }}.H ;;
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR12 ;;
    MULT.RC.VE LR3 CR1 0 LR11 {{ cr.ds_main }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds_main }}.L {{ cr.qf_in0 }}.L {{ cr.rotated }} LR11 ;;
    LD.MULT R0 LR11 {{ cr.rotated }} ;;
{% else %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR7 LR1 ; SET LR8 {{ cr.sizes }}.H ;;
{% endif %}
{{ tag }}_tile:
    SET LR9 CR0 ; SET LR10 LR8 ; BGE.S LR12 LR8 {{ tag }}_load ;;
    SET LR10 LR12 ;;
{{ tag }}_load:
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR11 ; DEC LR9 1 ; DEC LR10 1 ; BEQ LR10 CR1 {{ tag }}_last ;;
{{ tag }}_column:
    {{ dot(tag ~ '_column') }}
{{ tag }}_last:
    {{ dot('') }}
    BGE.S LR12 LR8 {{ tag }}_tail ;;
    {{ output(cr.ds_main ~ '.L') }}
    DEC LR8 128 ; B {{ tag }}_tile ;;
{{ tag }}_tail:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ; INC LR0 1 ; ADD LR6 LR6 {{ cr.strides }}.L ; DEC LR5 1 ; BNE LR5 CR1 {{ tag }}_row ;;
    B next_head ;;
{% endmacro %}
    BNE LR0 CR0 wide ;;
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ; SET LR4 {{ cr.heads }}.H ;;
    INC LR12 128 ; DEC LR0 1 ;;
head:
    SET LR5 {{ cr.sizes }}.L ; SET LR6 LR1 ;;
    BNE LR3 CR0 rotated_row ;;
    {{ rows('aligned', false) }}
    {{ rows('rotated', true) }}
next_head:
    ADD LR3 LR3 {{ cr.heads }}.L ; DEC LR4 1 ; BEQ LR4 CR1 done ;;
    BLT.S LR3 LR12 head ;;
    DEC LR3 128 ; INC LR1 1 ; B head ;;
done:
    HALT ;;

{# Each pass deinterleaves one feature bit and doubles the number of
   tokens contiguous in a row. Two input rows produce two output rows. #}
{% macro butterfly(rc, parity, dest, extra='') %}
    MULT.RC.VE {{ rc }} CR1 0 LR0 {{ cr.ds_main }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 {{ parity }} off {{ dest }} {{ extra }} ;;
{% endmacro %}
{% macro pass(stage, src, src_offset, dst_offset) %}
    SET LR3 {{ 'LR13' if stage == 0 else 'CR0' }} ; SET LR5 CR0 ; SET LR7 CR0 ;;
    {% if src_offset %} INC LR3 {{ src_offset }} ;; {% endif %}
    {% if dst_offset %} INC LR5 128 ;; {% endif %}
    {% if dst_offset == 256 %} INC LR5 128 ;; {% endif %}
    ADD LR4 LR3 LR8 ; DEC LR5 1 ; INC LR7 63 ;;
    LD.MULT.CYCLIC LR3 {{ src }} LR0 ; SET LR6 LR5 ;;
    LD.MULT.CYCLIC LR4 {{ src }} LR9 ; INC LR6 64 ;;
t{{ stage }}_pair:
    {{ butterfly('LR0', 'on', 'LR0', '; ADD LR3 LR4 LR8') }}
    {{ butterfly('LR9', 'on', 'LR10', '; ACTIVATE.QUANTIZE identity ' ~ cr.ds_main ~ '.L ' ~ cr.qf_in1 ~ '.L ' ~ cr.transpose ~ ' LR5 ; ADD LR4 LR3 LR8 ; INC LR5 1 ; BEQ LR7 CR0 t' ~ stage ~ '_last') }}
    {{ butterfly('LR0', 'on_inv', 'LR0', '; LD.MULT.CYCLIC LR3 ' ~ src ~ ' LR0') }}
    {{ butterfly('LR9', 'on_inv', 'LR10', '; ACTIVATE.QUANTIZE identity ' ~ cr.ds_main ~ '.L ' ~ cr.qf_in1 ~ '.L ' ~ cr.transpose ~ ' LR6 ; LD.MULT.CYCLIC LR4 ' ~ src ~ ' LR9 ; INC LR6 1 ; DEC LR7 1 ; B t' ~ stage ~ '_pair') }}
t{{ stage }}_last:
    {{ butterfly('LR0', 'on_inv', 'LR0') }}
    {{ butterfly('LR9', 'on_inv', 'LR10', '; ACTIVATE.QUANTIZE identity ' ~ cr.ds_main ~ '.L ' ~ cr.qf_in1 ~ '.L ' ~ cr.transpose ~ ' LR6 ; INC LR6 1') }}
{% endmacro %}
wide:
    SET LR0 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
wide_tile:
    SET LR14 CR0 ; SET LR15 LR12 ;;
wide_pair:
    SET LR9 CR0 ; SET LR10 CR1 ; SET LR8 {{ cr.strides }}.H ;;
    INC LR9 128 ; INC LR10 1 ;;
    {{ pass(0, cr.in1, 0, 0) }}
    SET LR8 CR1 ;;
    {% for s in range(1,7) %}
    {{ pass(s, cr.transpose, ((s-1)%2)*128, 256 if s==6 else (s%2)*128) }}
    {% endfor %}
    SET LR10 CR0 ; SUB LR8 LR15 {{ cr.tiles }} ; SET LR9 CR0 ;;
    INC LR9 127 ; DEC LR10 1 ;;
wide_head:
    SUB LR3 LR14 {{ cr.strides }}.L ; SET LR4 {{ cr.sizes }}.L ; SET LR6 LR10 ;;
    SET LR11 LR10 ; INC LR6 62 ;;
    INC LR11 128 ;;
    INC LR11 128 ;;
wide_row:
    LD.MULT R0 LR3 {{ cr.in0 }} ; SET LR5 LR10 ; ADD LR3 LR3 {{ cr.strides }}.L ; SET LR7 LR11 ;;
    LD.MULT.CYCLIC LR7 {{ cr.transpose }} LR0 ; INC LR7 1 ;;
{% macro product(first, extra) %}
    MULT.RC.VE LR0 LR5 0 LR0 {{ cr.ds_main }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} {{ extra }} ;;
{% endmacro %}
    {{ product(true, '; LD.MULT.CYCLIC LR7 ' ~ cr.transpose ~ ' LR0 ; INC LR7 1 ; INC LR5 1') }}
wide_k:
    {{ product(false, '; LD.MULT.CYCLIC LR7 ' ~ cr.transpose ~ ' LR0 ; INC LR7 1 ; INC LR5 1 ; BNE LR5 LR6 wide_k') }}
    {{ product(false, '; ACTIVATE.QUANTIZE ' ~ (act_out0 | default('identity')) ~ ' ' ~ cr.ds_main ~ '.L ' ~ cr.qf_out0 ~ '.L ' ~ cr.out0 ~ ' LR8 ; ADD LR8 LR8 ' ~ cr.tiles ~ ' ; INC LR5 1 ; DEC LR4 1 ; BNE LR4 CR1 wide_row') }}
    INC LR10 64 ;;
    BLT.S LR10 LR9 wide_head ;;
    INC LR14 1 ; INC LR13 1 ; ADD LR15 LR8 {{ cr.tiles }} ;;
    BLT.S LR14 LR2 wide_pair ;;
    SUB LR13 LR13 LR2 ; INC LR12 1 ;;
    ADD LR13 LR13 LR1 ; BLT.S LR12 {{ cr.tiles }} wide_tile ;;
    HALT ;;
