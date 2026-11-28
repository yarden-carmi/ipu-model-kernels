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
 SET LR1 CR0 ;;
 INC LR1 64 ;;
 BEQ LR1 {{ cr.n }} medium_check ;;
dot_select:
 SET LR0 CR0 ;;
 BLT.S LR7 {{ cr.n }} transpose_select ;;
 BLT.S LR7 {{ k }} transpose_select ;;
 ADD LR8 LR5 {{ k }} ; SET LR2 LR12 ; SET LR9 {{ m }} ;;
 BLT.S LR7 LR8 align ;;
 SET LR8 LR4 ; B dot_setup ;;
align:
 SET LR8 CR0 ; SET LR6 LR4 ; SET LR1 CR0 ;;
 INC LR1 128 ; SET LR3 {{ cr.n }} ; LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR0 ;;
 DEC LR8 1 ; DEC LR3 1 ; BEQ LR3 CR1 align_last ;;
align_column:
 LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR1 ; ADD LR7 LR6 CR1 ;;
 MULT.RC.VE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.bconfig }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR8 ; LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR0 ; ADD LR6 LR6 {{ bs }} ; INC LR8 1 ; DEC LR3 1 ; BNE LR3 CR1 align_column ;;
align_last:
 LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR1 ; ADD LR7 LR6 CR1 ;;
 MULT.RC.VE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.bconfig }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR8 ; ADD LR6 LR6 {{ bs }} ; INC LR8 1 ;;
 SET LR5 CR0 ; SET LR8 CR0 ; SUB LR4 LR6 LR4 ; B aligned_setup ;;
{% macro dot(tag, base, stride) %}
{{ tag }}_setup:
 SET LR3 {{ cr.n }} ; LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR11 1 ;;
 DEC LR3 1 ; DEC LR9 1 ;;
 SET LR1 LR3 ; BEQ LR9 CR0 {{ tag }}f_row ;;
 {% macro dots(label, prefetch) %}
{{ label }}_row:
 LD.MULT.CYCLIC LR8 {{ base }} LR0 ; SET LR6 LR8 ; SUB LR7 LR0 CR1 ; INC LR11 1 ; BEQ LR3 CR0 {{ label }}_last ;;
{{ label }}_column:
 MULT.RC.VV LR5 R0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR7 {{ cr.bconfig }}.H ; LD.MULT.CYCLIC LR6 {{ base }} LR0 ; ADD LR6 LR6 {{ stride }} ; INC LR7 1 ; DEC LR1 1 ; BNE LR1 CR1 {{ label }}_column ;;
{{ label }}_last:
 MULT.RC.VV LR5 R0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR3 {{ cr.bconfig }}.H ; {{ output('H') }} ; {% if prefetch %}LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR2 LR2 {{ ast }} ; SET LR1 LR3 ; DEC LR9 1 ; BNE LR9 CR1 {{ label }}_row ;{% endif %} ;;
 {% endmacro %}
 {{ dots(tag,true) }}
 {{ dots(tag~'f',false) }}
{% if tag == 'aligned' %}
 SET LR6 LR4 ;;
{% else %}
 SUB LR6 LR6 LR4 ;;
 ADD LR6 LR6 {{ bs }} ;;
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
 B blocked_panel ;;

medium_check:
 SET LR1 CR0 ; SET LR6 LR5 ;;
 INC LR1 48 ; INC LR6 48 ;;
 BEQ LR1 {{ k }} shuffle_panel ;;
 B dot_select ;;

{# Each stride pass trades lane bits for column bits. Scratch rows 0..47
   are the final panel; the four intermediate planes use 32 rows each. #}
shuffle_panel:
 SET LR0 CR0 ; SET LR1 CR1 ; SET LR2 CR1 ;;
 INC LR2 1 ; SET LR3 CR1 ; SET LR10 CR0 ;;
 INC LR3 2 ; BLT.S LR7 LR6 shuffle_cross ;;
{% macro shuffle_first(mode, parity, cross) %}
 SET LR6 LR4 ; SET LR7 CR0 ; SET LR8 CR0 ;;
 INC LR7 {{46+parity}} ; INC LR8 14 ; LD.MULT R0 LR6 {{ cr.in1 }} ;;
 {% for tail in [false,true] %}
 {% if not tail %} shuffle_first_{{parity}}_{{cross}}: {% endif %}
 {% for j in range(4) %}
 {% if cross %} ADD LR9 LR6 CR1 ; LD.MULT R1 LR9 {{ cr.in1 }} ;; {% endif %}
 MULT.VE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 {{mode}} on LR{{j}} ; ADD LR6 LR6 {{bs}} ; {% if not tail or not loop.last %} LD.MULT R0 LR6 {{ cr.in1 }} ; {% endif %} {% if loop.last %} INC LR7 2 ; {{panel('L','LR7')}} ; {% if not tail %} DEC LR8 1 ; BNE LR8 CR0 shuffle_first_{{parity}}_{{cross}} ; {% endif %} {% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{{ shuffle_first('on',0,false) }}
{{ shuffle_first('on_inv',1,false) }}
 B shuffle_second ;;
shuffle_cross:
{{ shuffle_first('on',0,true) }}
{{ shuffle_first('on_inv',1,true) }}
shuffle_second:
 BNE LR14 CR1 shuffle_s2_start ;;
 SUB LR6 LR6 LR4 ;;
 ADD LR13 LR13 LR6 ;;
shuffle_s2_start:
{% for mode in range(4) %}
 SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
 INC LR6 48 ; INC LR7 {{73+2*mode}} ; INC LR8 3 ; LD.MULT R0 LR6 {{cr.panel}} ;;
shuffle_s2_{{mode}}:
 {% for p in range(2) %}
 {% for j in range(4) %}
 MULT.VE LR0 CR1 0 LR0 {{cr.ds}}.L {{cr.qf_in1}}.L ; ACC.STRIDE 16 {{'on_inv' if mode%2 else 'on'}} {{'on_inv' if mode>=2 else 'on'}} LR{{j}} ;
 {% if not loop.last %} INC LR6 2 ; {% elif p == 0 %} DEC LR6 5 ; INC LR7 7 ; {{panel('L','LR7')}} ; {% else %} INC LR6 1 ; INC LR7 1 ; {{panel('L','LR7')}} ; DEC LR8 1 ; BNE LR8 CR0 shuffle_s2_{{mode}} ; {% endif %}
 LD.MULT R0 LR6 {{cr.panel}} ;;
 {% endfor %}
 {% endfor %}
{% endfor %}
{# S2 output pairs are adjacent; its destination cursor advances by eight
   after each pair (the first store above starts at the pair's first row). #}
{% macro shuffle_merge(stage,mode,group,src,gap,dest) %}
 SET LR6 CR0 ; SET LR7 CR0 ; SET LR9 CR0 ;;
 INC LR6 {{src}} ; INC LR7 {{dest-1}} ; SET LR8 CR0 ; LD.MULT R0 LR6 {{cr.panel}} ;;
 INC LR9 {{src+gap-1}} ; INC LR8 {{group-1}} ;;
shuffle_merge_{{stage}}:
 MULT.VE LR0 CR1 0 LR0 {{cr.ds}}.L {{cr.qf_in1}}.L ; ACC.STRIDE 16 {{mode}} off LR0 ; LD.MULT R0 LR9 {{cr.panel}} ; INC LR9 1 ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.ds}}.L {{cr.qf_in1}}.L ; ACC.STRIDE 16 {{mode}} off LR2 ; INC LR6 1 ; LD.MULT R0 LR6 {{cr.panel}} ; INC LR7 1 ; {{panel('L','LR7')}} ; DEC LR8 1 ; BNE LR8 CR0 shuffle_merge_{{stage}} ;;
{% endmacro %}
{# Keep k5 next to the previously extracted bits until the final unpack. #}
{% for c in range(2) %}
 {{shuffle_merge('s3_'~c~'_0','on',8,80+c*16,8,112+c*16)}}
 {{shuffle_merge('s3_'~c~'_1','on_inv',8,80+c*16,8,120+c*16)}}
{% endfor %}
{{shuffle_merge('s4_0','on',16,112,16,144)}}
{{shuffle_merge('s4_1','on_inv',16,112,16,160)}}
{# Rows are ordered [k3,k2,k5,k1,k0], lanes [column,k4]. #}
 SET LR6 CR0 ; SET LR4 CR0 ;;
 INC LR6 144 ; DEC LR4 1 ;;
{% for g in range(8) %}
 {% set high = g%2 %}
 {% set idx = (g//2)*4 %}
 SET LR8 LR4 ; SET LR9 CR0 ; SET LR5 LR4 ; LD.MULT R0 LR6 {{cr.panel}} ;;
 INC LR8 {{(32 if high else 0)+idx}} ; INC LR9 3 ; INC LR5 {{16+idx}} ;;
shuffle_unpack_{{g}}:
 MULT.VE LR0 CR1 0 LR0 {{cr.ds}}.L {{cr.qf_in1}}.L ; ACC.STRIDE 16 on off LR0 ; {{ panel('H','LR8') }} ; INC LR8 1 ; {% if high %} INC LR6 1 ; LD.MULT R0 LR6 {{cr.panel}} ; DEC LR9 1 ; BNE LR9 CR0 shuffle_unpack_{{g}} ; {% endif %} ;;
 {% if not high %}
 MULT.VE LR0 CR1 0 LR0 {{cr.ds}}.L {{cr.qf_in1}}.L ; ACC.STRIDE 16 on_inv off LR0 ; {{panel('H','LR5')}} ; INC LR6 1 ; LD.MULT R0 LR6 {{cr.panel}} ; INC LR5 1 ; DEC LR9 1 ; BNE LR9 CR0 shuffle_unpack_{{g}} ;;
 {% endif %}
{% endfor %}
 B block_compute ;;

{# Create little-endian byte bundles, three registers at a time. #}
{% macro seed() %}
 BNE LR0 CR0 seed_cached ;;
 INC LR0 3 ;;
 {% for i in range(8) %} ADD LR0 LR0 LR0 ;; {% endfor %}
 INC LR0 2 ;;
 {% for i in range(8) %} ADD LR0 LR0 LR0 ;; {% endfor %}
 INC LR0 1 ;;
 {% for i in range(8) %} ADD LR0 LR0 LR0 ;; {% endfor %}
seed_cached:
 SET LR3 LR0 ; SET LR2 LR0 ;;
 ADDBI LRD2 4 ;;
 SET LR1 LR3 ; SET LR2 LR0 ;;
 {% for i in range(4) %} ADD LR2 LR2 LR2 ; ADD LR3 LR3 LR3 ;; {% endfor %}
{% endmacro %}

blocked_panel:
 {{ seed() }}
 SET LR9 LR10 ; SET LR8 LR10 ; SET LR6 CR0 ;;
 INC.MODP2 LR9 CR0 7 ; INC.MODP2 LR8 CR0 3 ; SET LR7 {{ tiles }} ;;
 SUB LR9 LR9 LR8 ; ADD LR8 LR8 {{ k }} ;;
 SET LR10 CR0 ;;
block_reserve:
 ADD LR6 LR6 {{ k }} ; DEC LR7 1 ; BNE LR7 CR1 block_reserve ;;
 DEC LR6 1 ;;
block_k:
 SET LR7 {{ cr.n }} ; SET LR5 LR4 ;;
 DEC LR7 16 ;;
 LD.MULT R0 LR5 {{ cr.in1 }} ;;
 B block_n ;;
block_n_load:
 LD.MULT R0 LR5 {{ cr.in1 }} ; ADD LR5 LR5 {{ bs }} ; ADDBI LRD2 -15 ;;
block_n:
 {% for i in range(16) %}
 MULT.VE LR9 CR1 0 LR10 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;
 {% if not loop.last %}
 LD.MULT R0 LR5 {{ cr.in1 }} ; ADD LR5 LR5 {{ bs }} ; {% if i %}ADDBI LRD2 1 ;{% endif %} ;;
 {% else %}
 {{ panel('L','LR6') }} ; ADDBI LRD2 1 ; INC LR6 1 ; DEC LR7 16 ; BLT.S CR0 LR7 block_n_load ;;
 {% endif %}
 {% endfor %}
 ADD LR5 LR5 {{ bs }} ; ADDBI LRD2 -15 ; DEC LR8 8 ;;
block_k_next:
 BLE.S LR8 CR0 block_span_select ;;
 INC LR9 8 ;;
 INC.MODP2 LR9 CR0 7 ;;
 BNE LR9 CR0 block_k ;;
 INC LR4 1 ; B block_k ;;

block_span_select:
 BNE LR14 CR1 block_join_setup ;;
 SUB LR5 LR5 LR4 ;;
 ADD LR13 LR13 LR5 ;;

block_join_setup:
 SET LR8 CR0 ; SET LR7 {{ tiles }} ; SET LR5 CR0 ;;
block_join_base:
 ADD LR8 LR8 {{ k }} ; DEC LR7 1 ; BNE LR7 CR1 block_join_base ;;
 DEC LR5 1 ;;
wide_join_setup:
 {# Deinterleave the two low K bits in place. Each stride packs 64
    values, so a pair of rows can be joined without eight-lane scatters. #}
 SET LR1 CR0 ; SET LR2 CR1 ; SET LR3 LR8 ;;
 INC LR1 128 ; INC LR2 1 ;;
 {% macro split_pair(step,advance,tag) %}
 {{ tag }}:
  LD.MULT R0 LR3 {{ cr.panel }} ; SET LR4 LR3 ;;
   MULT.VE LR10 CR1 0 LR10 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 off on LR10 ; INC LR4 {{ step }} ; LD.MULT R1 LR4 {{ cr.panel }} ;;
   MULT.VE LR1 CR1 0 LR10 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 off on LR2 ; {{ panel('L','LR3') }} ;;
   MULT.VE LR10 CR1 0 LR10 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 off on_inv LR10 ;;
   MULT.VE LR1 CR1 0 LR10 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 off on_inv LR2 ; {{ panel('L','LR4') }} ; INC LR3 {{ advance }} ; BNE LR4 LR6 {{ tag }} ;;
 {% endmacro %}
 {{ split_pair(1,2,'wide_split_low') }}
 SET LR3 LR8 ; DEC LR6 1 ;;
 {{ split_pair(2,4,'wide_split_even') }}
 SET LR3 LR8 ; INC LR6 1 ;;
 INC LR3 1 ;;
 {{ split_pair(2,4,'wide_split_odd') }}
 SET LR7 {{ cr.in0_d1 }} ; SET LR6 CR0 ;;
 ADD LR7 LR7 {{ cr.in0_d1 }} ;;
 SUB LR7 LR7 LR14 ;;
join_head_offset:
 ADD LR6 LR6 {{ k }} ; DEC LR7 1 ; BNE LR7 CR1 join_head_offset ;;
 INC.MODP2 LR6 CR0 3 ; SET LR9 {{ k }} ;;
 SET LR7 CR0 ; SET LR3 CR1 ;;
 INC LR7 4 ; INC LR3 1 ;;
block_join_k:
 SET LR4 LR6 ; SET LR2 {{ tiles }} ;;
 INC.MODP2 LR4 CR0 2 ;;
 ADD LR4 LR4 LR8 ; BGE.S LR6 LR7 block_join_odd ;;
 {% macro wide_finish(tag,mode) %}
 {{ tag }}:
 LD.MULT R0 LR4 {{ cr.panel }} ; DEC LR2 1 ;;
 MULT.VE LR10 CR1 0 LR10 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 off {{ mode }} LR10 ; INC LR4 4 ; LD.MULT R1 LR4 {{ cr.panel }} ;;
 MULT.VE LR1 CR1 0 LR10 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 off {{ mode }} LR3 ; {{ panel('L','LR5') }} ; INC LR5 1 ; INC LR4 4 ; BNE LR2 CR0 {{ tag }} ;;
 {% endmacro %}
 {{ wide_finish('block_join_even','on') }}
 B block_join_next ;;
 {{ wide_finish('block_join_odd','on_inv') }}
block_join_next:
 DEC LR9 1 ; BEQ LR9 CR1 block_compute ;;
 INC.MODP2 LR6 CR1 3 ;;
 BNE LR6 CR0 block_join_k ;;
 DEC LR4 3 ;;
 SET LR8 LR4 ; B block_join_k ;;

block_compute:
 DEC LR14 1 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 INC LR4 128 ; INC LR5 128 ; SET LR1 CR0 ;;
 INC LR5 128 ; SET LR9 LR11 ; SET LR7 {{ tiles }} ;;

wide_tile:
 SET LR2 LR12 ; SET LR3 {{ m }} ; SUB LR11 LR9 {{ tiles }} ;;
 LD.MULT.CYCLIC LR1 {{ cr.panel }} LR4 ; SET LR8 LR1 ; DEC LR3 1 ;;
 LD.MULT.CYCLIC LR8 {{ cr.panel }} LR5 ; ADD LR8 LR8 {{ tiles }} ;;
 LD.MULT R0 LR2 {{ cr.in0 }} ; BEQ LR3 CR0 wide_final_row ;;
{% macro wide_row(tag, prefetch) %}
{{ tag }}_row:
 MULT.RC.VE LR4 LR10 0 LR10 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ADD LR8 LR1 {{ tiles }} ; SET LR6 CR0 ; ADD LR11 LR11 {{ tiles }} ;;
 MULT.RC.VE LR5 LR6 0 LR10 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR8 {{ cr.panel }} LR10 ; ADD LR8 LR8 {{ tiles }} ; INC LR6 1 ;;
{{ tag }}_reduce:
 MULT.RC.VE LR10 LR6 0 LR10 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR8 {{ cr.panel }} LR10 ; ADD LR8 LR8 {{ tiles }} ; INC LR6 1 ; BLT.S LR6 {{ cr.kconfig }}.H {{ tag }}_reduce ;;
 MULT.RC.VE LR10 LR6 0 LR10 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ output('H') }} ; INC LR6 1 ; {% if prefetch %}ADD LR2 LR2 {{ ast }} ; LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR3 1 ; BNE LR3 CR1 {{ tag }}_row ;{% endif %} ;;
{% endmacro %}
{# Count rows after this one so the penultimate drain can prefetch the last. #}
{{ wide_row('wide',true) }}
{{ wide_row('wide_final',false) }}
 INC LR9 1 ; INC LR1 1 ; DEC LR7 1 ;;
 BNE LR7 CR0 wide_tile ;;
 INC LR11 1 ; SET LR7 {{ cr.in0_d1 }} ; BEQ LR14 CR0 group_done ;;
 ADD LR7 LR7 {{ cr.in0_d1 }} ;;
 SUB LR7 LR7 LR14 ;;
restore_head_offset:
 ADD LR10 LR10 {{ k }} ; DEC LR7 1 ; BNE LR7 CR1 restore_head_offset ;;
 ADD LR12 LR12 {{ ar }} ; B head ;;

{# General transpose for tails and reductions spanning multiple A rows. #}
generic_transpose:
 SET LR7 CR0 ; SET LR0 CR0 ;;
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
