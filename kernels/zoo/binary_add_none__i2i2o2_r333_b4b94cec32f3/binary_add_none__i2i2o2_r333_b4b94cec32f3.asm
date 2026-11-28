{% set fast = out0_d0 % 2 == 0 and (out0_d0 * out0_d1) % 128 == 0 %}
{% set fast = fast and out0_d2 % 64 == 0 and out0_d2 <= 256 and out0_d0 * out0_d1 <= 32640 and (out0_d1 - 1) * ((out0_d2 + 127) // 128) <= 8160 %}
{% if fast %}
{% set S = out0_d0 * out0_d1 %}
{% set W = (out0_d2 + 127) // 128 %}
{% set P = out0_d2 // 64 %}
{% macro advance(reg, n) %}{% for i in range((n + 254) // 255) %}INC {{ reg }} {{ [255, n - 255 * i] | min }} ;;{% endfor %}{% endmacro %}
{% macro transpose(first_tile, tile, fmt) %}
    SET LR4 {{ cr.tail }} ; SET LR5 {{ cr.end_width }} ; SET LR12 CR0 ;;
    {% if tile %}INC LR12 {{ tile }} ;;{% endif %}
    LD.MULT R0 LR12 {{ cr.span }} ;;
    {% for j in range(8) %}
    MULT.VE LR11 CR1 0 LR0 CR15.L {{ fmt }} ; ACC.RESHAPE LRD4 LRD2 0 ; {% if j %}ADDBI LRD4 16 ;{% endif %}{% if j or not first_tile %}ADDBI LRD2 8 ;{% endif %} ;;
    {% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
    SET LR9 LR8 ; SET LR10 CR0 ; SET LR14 CR0 ;;
    {{ advance('LR14', out0_d1 - 1) }}
fast_batch:
    SET LR13 LR1 ; SET LR15 CR0 ;;
    {{ advance('LR15', out0_d0 // 2 - 1) }}
fast_group:
    SET LR6 LR10 ;;
    {% for t in range(P) %}
    SET LR2 CR0 ; SET LR3 LR8 ; SET LR11 CR0 ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
    INC LR11 61 ;;
    MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD8 LRD2 6 ; INC LR6 {{ S // 128 }} ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
fast_gather_{{ t }}:
    MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD8 LRD2 6 ; ADDBI LRD2 2 ; INC LR6 {{ S // 128 }} ; DEC LR11 1 ; LD.MULT R0 LR6 {{ cr.in0 }} ; BNE LR11 CR0 fast_gather_{{ t }} ;;
    MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD8 LRD2 6 ; ADDBI LRD2 2 ; INC LR6 {{ S // 128 }} ;;
    SET LR12 CR0 ;;
    {% if t %}INC LR12 {{ 2*t }} ;;{% endif %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.step_row }}.L {{ cr.span }} LR12 ;;
    LD.MULT R0 LR12 {{ cr.span }} ;;
    INC LR12 1 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.step_row }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.step_row }}.H {{ cr.span }} LR12 ;;
    {% endfor %}
    {% for a in range(2) %}
    SET LR11 {{ 'CR0' if a == 0 else 'CR1' }} ;;
    {% for chunk in range((P + 1) // 2) %}
    SET LR2 {{ cr.step_lane }} ; SET LR3 {{ cr.dims }} ;;
    {% for j in range([2, P - 2*chunk] | min) %}{{ transpose(j == 0, 2*(2*chunk+j)+1, cr.step_row ~ '.H') }}{% endfor %}
    SET LR12 CR0 ;;
    INC LR12 {{ 2*P }} ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.step_row }}.H {{ cr.span }} LR12 ;;
    SET LR2 {{ cr.step_lane }} ; SET LR3 {{ cr.dims }} ;;
    {% for j in range([2, P - 2*chunk] | min) %}{{ transpose(j == 0, 2*(2*chunk+j), cr.step_row ~ '.L') }}{% endfor %}
    SET LR12 CR0 ;;
    INC LR12 {{ 2*P }} ;;
    LD.MULT R0 LR12 {{ cr.span }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.step_row }}.H ; ACC.ADD ; LD.MULT R0 LR13 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.scalar ~ '.L' if chunk == (P-1)//2 else 'CR15.L' }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
    {% endfor %}
    {{ advance('LR13', out0_d1 * W - W) }}
    {% endfor %}
    INC LR7 2 ; SET LR6 CR0 ;;
    INC LR6 128 ;;
    BLT.S LR7 LR6 fast_lane_ok ;;
    DEC LR7 128 ; INC LR10 1 ;;
fast_lane_ok:
    DEC LR15 1 ; BNE LR15 CR0 fast_group ;;
    {{ advance('LR1', W) }}
    DEC LR14 1 ; BNE LR14 CR0 fast_batch ;;
    HALT ;;
{% else %}
{% set dense = (in0_d1 * in0_d2) % 128 == 0 %}
{% set lane_span = 128 if dense else in0_d2 %}
{% set paired = dense and out0_d0 * out0_d1 == 64 and out0_d2 % 2 == 0 and out0_d2 >= 6 and out0_d2 % 128 not in [2, 4] %}
{% set row_step = out0_d0 * out0_d1 // 128 %}
{% set pipeline = dense and (out0_d0 * out0_d1) % 128 == 0 and row_step <= 127 %}
{% macro store(mask) %}
    LD.MULT R0 LR1 {{ cr.in1 }} ; SET LR2 CR0 ; SET LR3 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
{% macro gather_lane(offset) %}
    MULT.EE {{ offset }} CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.scalar }}.L ; INC LR2 1 ;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR14 CR0 ;;
    SET LR13 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR13 128 ;;
{% if paired %}
    SET LR9 LR8 ;;
    {% for i in range(6) %}ADD LR9 LR9 LR9 ;;{% endfor %}
{% endif %}
batch:
    SET LR4 CR0 ; SET LR5 LR14 ; SET LR15 {{ cr.dims }}.H ;;
// The row starts at flat storage offset a + A*b; c advances by A*B.
origin:
    BLT.S LR5 {{ cr.span }}.L row ;;
    SUB LR5 LR5 {{ cr.span }}.L ; ADD LR4 LR4 {{ cr.span }}.H ; B origin ;;
row:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR12 {{ cr.end_width }} ;;
chunk:
    BGE.S LR13 LR12 tail_chunk ; SET LR11 LR12 ;;
    SET LR11 LR13 ; DEC LR12 128 ; B start_gather ;;
tail_chunk:
    SET LR12 CR0 ;;
start_gather:
// AGG sees the incremented destination; the branch sees the old cursor.
{% if paired %}
// The row origin is below lane 64, so each loaded row supplies two values.
// Load the next pair alongside the second gather, leaving the final pair
// separate so the last chunk never reads beyond the input.
    SET LR2 CR0 ; SET LR3 LR8 ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
    DEC LR11 6 ;;
    MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD8 LRD2 6 ; INC LR6 1 ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
pair_next:
    MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD8 LRD2 6 ; ADDBI LRD2 2 ; INC LR6 1 ; DEC LR11 2 ; LD.MULT R0 LR6 {{ cr.in0 }} ; BNE LR11 CR0 pair_next ;;
    MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD8 LRD2 6 ; ADDBI LRD2 2 ; INC LR6 1 ;;
{% elif pipeline %}
// Whole-row strides keep the source lane fixed. Bundle the next load
// with each gather, peeling the last lane to avoid a speculative read.
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR2 1 ; BEQ LR11 CR1 gather_last ;;
    DEC LR11 3 ;;
gather_next:
    {{ gather_lane('LR7') }} INC LR6 {{ row_step }} ; LD.MULT R0 LR6 {{ cr.in0 }} ; BNE LR2 LR11 gather_next ;;
gather_last:
    {{ gather_lane('LR7') }} INC LR6 {{ row_step }} ;;
{% else %}
    DEC LR2 1 ; DEC LR11 2 ;;
 gather:
{% if (out0_d0 * out0_d1) % lane_span != 0 %}
    BLT.S LR7 {{ cr.span }}.L locate ;;
    SUB LR7 LR7 {{ cr.span }}.L ; ADD LR6 LR6 {{ cr.span }}.H ;;
locate:
{% endif %}
{% if dense or in0_d2 <= 128 %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ;;
{% elif in0_d2 <= 256 %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR7 ; ADD LR10 LR6 CR1 ; BLT.S LR7 LR13 loaded ;;
    LD.MULT R0 LR10 {{ cr.in0 }} ; SUB LR9 LR7 LR13 ;;
loaded:
{% else %}
    SET LR10 LR6 ; SET LR9 LR7 ;;
physical_chunk:
    BLT.S LR9 LR13 load ;;
    INC LR10 1 ; DEC LR9 128 ; B physical_chunk ;;
load:
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% endif %}
    {{ gather_lane('LR9') }} ADD LR6 LR6 {{ cr.step_row }} ; ADD LR7 LR7 {{ cr.step_lane }} ; BNE LR2 LR11 gather ;;
{% endif %}
    BEQ LR12 CR0 end_row ;;
    {{ store('CR15.L') }}
    B chunk ;;
end_row:
    {{ store(cr.tail ~ '.L') }}
    DEC LR15 1 ; ADD LR5 LR5 {{ cr.dims }}.L ;;
    BNE LR15 CR0 origin ;;
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.dims }}.L batch ;;
    HALT ;;
{% endif %}
