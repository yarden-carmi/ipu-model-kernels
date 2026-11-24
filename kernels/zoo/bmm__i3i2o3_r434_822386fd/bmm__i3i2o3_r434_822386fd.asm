{% set k = cr.kconfig ~ '.L' %}
{% set m = cr.mconfig ~ '.L' %}
{% set tiles = cr.mconfig ~ '.H' %}
{% set bs = cr.bconfig ~ '.L' %}
{% set ast = cr.astride ~ '.L' %}
{% set ar = cr.astride ~ '.H' %}
{% macro output(half) -%}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11
{%- endmacro %}
{% macro panel(half,ptr) -%}
 ACTIVATE.QUANTIZE identity {{ cr.ds }}.{{ half }} {{ cr.qf_in1 }}.L {{ cr.panel }} {{ ptr }}
{%- endmacro %}
group:
 SET LR14 {{ cr.in0_d1 }} ; SET LR10 CR0 ; SET LR1 {{ cr.in0_d1 }} ;;
group_offset:
 ADD LR10 LR10 {{ k }} ; DEC LR1 1 ; BNE LR1 CR1 group_offset ;;
head:
 SET LR4 LR13 ; SET LR5 LR10 ; SET LR7 CR0 ;;
 INC LR7 128 ;;
normalize:
 BLT.S LR5 LR7 select ;;
 DEC LR5 128 ; INC LR4 1 ; B normalize ;;
select:
 BLT.S LR7 {{ cr.n }} transpose_select ;;
 BLT.S LR7 {{ k }} transpose_select ;;
 ADD LR8 LR5 {{ k }} ; SET LR2 LR12 ; SET LR9 {{ m }} ;;
 BLT.S LR7 LR8 align ;;
 SET LR8 LR4 ; B dot_setup ;;
align:
 SET LR8 CR0 ; SET LR6 LR4 ; SET LR1 CR0 ;;
 INC LR1 128 ; SET LR3 {{ cr.n }} ;;
align_column:
 LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR0 ; ADD LR7 LR6 CR1 ;;
 LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR1 ; ADD LR6 LR6 {{ bs }} ;;
 MULT.RC.VE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.bconfig }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR8 ;;
 INC LR8 1 ; DEC LR3 1 ; BNE LR3 CR1 align_column ;;
 SET LR5 CR0 ; SET LR8 CR0 ; SUB LR4 LR6 LR4 ; B aligned_setup ;;
{% macro dot(tag, base, stride) %}
{{ tag }}_setup:
 SET LR3 {{ cr.n }} ;;
 DEC LR3 1 ;;
{{ tag }}_row:
 LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR6 LR8 ; SET LR7 CR0 ; SET LR1 LR3 ;;
 LD.MULT.CYCLIC LR6 {{ base }} LR0 ; DEC LR7 1 ; BEQ LR3 CR0 {{ tag }}_last ;;
{{ tag }}_column:
 MULT.RC.VV LR5 R0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR7 {{ cr.bconfig }}.H ; LD.MULT.CYCLIC LR6 {{ base }} LR0 ; ADD LR6 LR6 {{ stride }} ; INC LR7 1 ; DEC LR1 1 ; BNE LR1 CR1 {{ tag }}_column ;;
{{ tag }}_last:
 MULT.RC.VV LR5 R0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR7 {{ cr.bconfig }}.H ; INC LR7 1 ; {{ output('H') }} ; DEC LR9 1 ; BEQ LR9 CR1 {{ tag }}_done ;;
 INC LR11 1 ; ADD LR2 LR2 {{ ast }} ; B {{ tag }}_row ;;
{{ tag }}_done:
{% if tag == 'aligned' %}
 SET LR6 LR4 ;
{% else %}
 SUB LR6 LR6 LR4 ;;
 ADD LR6 LR6 {{ bs }} ;
{% endif %}
 INC LR11 1 ; DEC LR14 1 ;;
 BNE LR14 CR0 head_done ;;
 ADD LR13 LR13 LR6 ; B head_done ;;
{% endmacro %}
{{ dot('dot', cr.in1, bs) }}
{{ dot('aligned', cr.panel, 'CR1') }}
head_done:
 BEQ LR14 CR0 group_done ;;
 ADD LR12 LR12 {{ ar }} ; ADD LR10 LR10 {{ k }} ; B head ;;
group_done:
 ADD LR12 LR2 {{ ar }} ; DEC LR15 1 ;;
 BNE LR15 CR0 group ;;
 HALT ;;

transpose_select:
 SET LR1 {{ cr.n }} ; SET LR7 CR0 ;;
 INC.MODP2 LR1 CR0 7 ; INC LR7 128 ;;
 BNE LR1 CR0 generic_transpose ;;
 BLT.S LR7 {{ k }} generic_transpose ;;
 BLT.S {{ cr.kconfig }}.H CR1 generic_transpose ;;

{# Full-width tiles: gather B in tile-major order, one column per word. #}
 SET LR7 LR4 ; SET LR8 CR0 ; SET LR9 {{ cr.n }} ;;
wide_panel_tile:
 SET LR5 LR10 ; SET LR4 LR7 ; SET LR2 {{ k }} ;;
 INC.MODP2 LR5 CR0 7 ;;
wide_panel_row:
 SET LR6 LR4 ; SET LR3 CR0 ; SET LR1 CR0 ; LD.MULT R0 LR6 {{ cr.in1 }} ;;
 MULT.EE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; LD.MULT R0 LR6 {{ cr.in1 }} ; ADD LR6 LR6 {{ bs }} ; INC LR1 126 ;;
wide_gather:
 MULT.EE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; LD.MULT R0 LR6 {{ cr.in1 }} ; ADD LR6 LR6 {{ bs }} ; ADDBI LRD2 1 ; DEC LR1 1 ; BNE LR1 CR1 wide_gather ;;
 MULT.EE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADDBI LRD2 1 ; {{ panel('L','LR8') }} ;;
 ADDBI LRD2 -127 ; INC LR8 1 ; INC.MODP2 LR5 CR1 7 ;;
 DEC LR2 1 ; BEQ LR2 CR1 wide_panel_tile_done ;;
 BNE LR5 CR0 wide_panel_row ;;
 INC LR4 1 ; B wide_panel_row ;;
wide_panel_tile_done:
 SUB LR6 LR6 LR4 ; DEC LR9 128 ;;
 ADD LR6 LR6 {{ bs }} ;;
 ADD LR7 LR7 LR6 ; BEQ LR14 CR1 wide_group_span ;;
 B wide_panel_next ;;
wide_group_span:
 ADD LR13 LR13 LR6 ;;
wide_panel_next:
 BNE LR9 CR0 wide_panel_tile ;;
 DEC LR14 1 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 INC LR4 128 ; INC LR5 128 ; SET LR1 CR0 ;;
 INC LR5 128 ; SET LR9 LR11 ; SET LR7 {{ tiles }} ;;
wide_tile:
 SET LR2 LR12 ; SET LR3 {{ m }} ; SUB LR11 LR9 {{ tiles }} ;;
 LD.MULT.CYCLIC LR1 {{ cr.panel }} LR4 ; SET LR8 LR1 ; DEC LR3 1 ;;
 LD.MULT.CYCLIC LR8 {{ cr.panel }} LR5 ; INC LR8 1 ;;
 LD.MULT R0 LR2 {{ cr.in0 }} ; BEQ LR3 CR0 wide_final_row ;;
{% macro wide_row(tag, prefetch) %}
{{ tag }}_row:
 MULT.RC.VE LR4 LR0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR8 LR1 ; SET LR6 CR0 ; ADD LR11 LR11 {{ tiles }} ;;
 MULT.RC.VE LR5 LR6 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR8 {{ cr.panel }} LR0 ; INC LR8 2 ; INC LR6 1 ;;
{{ tag }}_reduce:
 MULT.RC.VE LR0 LR6 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR8 {{ cr.panel }} LR0 ; INC LR8 1 ; INC LR6 1 ; BLT.S LR6 {{ cr.kconfig }}.H {{ tag }}_reduce ;;
 MULT.RC.VE LR0 LR6 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ output('L') }} ; INC LR6 1 ; {% if prefetch %}ADD LR2 LR2 {{ ast }} ; LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR3 1 ; BNE LR3 CR1 {{ tag }}_row ;{% endif %} ;;
{% endmacro %}
{# Count rows after this one so the penultimate drain can prefetch the last. #}
{{ wide_row('wide',true) }}
{{ wide_row('wide_final',false) }}
 INC LR9 1 ; ADD LR1 LR1 {{ k }} ; DEC LR7 1 ;;
 BNE LR7 CR0 wide_tile ;;
 INC LR11 1 ; B head_done ;;

{# General transpose for tails and reductions spanning multiple A rows. #}
generic_transpose:
 SET LR7 CR0 ;;
generic_k:
 SET LR6 LR4 ; SET LR8 LR7 ; SET LR9 {{ cr.n }} ;;
generic_panel_tile:
 SET LR3 CR0 ; SET LR1 CR0 ; LD.MULT R0 LR6 {{ cr.in1 }} ;;
 MULT.EE LR5 CR0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; INC LR1 128 ;;
 BLT.S LR1 LR9 generic_width ;;
 SET LR1 LR9 ;;
generic_width:
 DEC LR1 1 ;;
 BEQ LR1 CR0 generic_drain ;;
 MULT.EE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; LD.MULT R0 LR6 {{ cr.in1 }} ; ADD LR6 LR6 {{ bs }} ; DEC LR1 1 ; BEQ LR1 CR1 generic_advance ;;
generic_gather:
 MULT.EE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; LD.MULT R0 LR6 {{ cr.in1 }} ; ADD LR6 LR6 {{ bs }} ; ADDBI LRD2 1 ; DEC LR1 1 ; BNE LR1 CR1 generic_gather ;;
generic_advance:
 ADDBI LRD2 1 ;;
generic_drain:
 MULT.EE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR6 LR6 {{ bs }} ;;
 SET LR1 CR0 ;;
 INC LR1 128 ;;
 BLT.S LR1 LR9 generic_full ;;
 {{ panel('H','LR8') }} ; INC LR7 1 ; INC LR5 1 ;;
 BGE.S LR7 {{ k }} generic_panel_done ;;
 INC.MODP2 LR5 CR0 7 ;;
 BNE LR5 CR0 generic_k ;;
 INC LR4 1 ; B generic_k ;;
generic_full:
 {{ panel('L','LR8') }} ;;
 DEC LR9 128 ; ADD LR8 LR8 {{ k }} ; B generic_panel_tile ;;
generic_panel_done:
 SUB LR6 LR6 LR4 ; DEC LR14 1 ;;
 BNE LR14 CR0 generic_multiply ;;
 ADD LR13 LR13 LR6 ;;
generic_multiply:
 SET LR9 {{ m }} ; SET LR2 LR12 ; SET LR3 CR0 ;;
 INC LR3 128 ;;
generic_row:
 SET LR8 CR0 ; SET LR4 {{ cr.n }} ;;
generic_tile:
 SET LR5 LR2 ; SET LR7 {{ k }} ;;
 MULT.VE LR0 CR0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
generic_chunk:
 LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR6 CR0 ; SET LR1 LR7 ;;
 INC LR5 1 ; DEC LR6 1 ;;
 BLE.S LR1 LR3 generic_count ;;
 SET LR1 LR3 ;;
generic_count:
 SUB LR7 LR7 LR1 ;;
 LD.MULT.CYCLIC LR8 {{ cr.panel }} LR0 ; DEC LR1 1 ;;
 BEQ LR1 CR0 generic_last ;;
generic_reduce:
 MULT.RC.VE LR0 LR6 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR8 {{ cr.panel }} LR0 ; INC LR8 1 ; INC LR6 1 ; DEC LR1 1 ; BNE LR1 CR1 generic_reduce ;;
generic_last:
 MULT.RC.VE LR0 LR6 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR8 1 ; INC LR6 1 ; BNE LR7 CR0 generic_chunk ;;
 BLT.S LR3 LR4 generic_store_full ;;
 {{ output('H') }} ; DEC LR9 1 ; BEQ LR9 CR1 generic_done ;;
 INC LR11 1 ; ADD LR2 LR2 {{ ast }} ; B generic_row ;;
generic_done:
 INC LR11 1 ; B head_done ;;
generic_store_full:
 {{ output('L') }} ; DEC LR4 128 ;;
 INC LR11 1 ; B generic_tile ;;
