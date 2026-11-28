{% set k = cr.kconfig ~ '.L' %}
{% set m = cr.mconfig ~ '.L' %}
{% set tiles = cr.mconfig ~ '.H' %}
{% set stride = cr.bconfig ~ '.L' %}
{% set hstep = cr.astride ~ '.L' %}
{% set start = cr.astride ~ '.H' %}
{% macro seed() %}
 INC LR0 3 ;;
 {% for i in range(8) %} ADD LR0 LR0 LR0 ;; {% endfor %}
 INC LR0 2 ;;
 {% for i in range(8) %} ADD LR0 LR0 LR0 ;; {% endfor %}
 INC LR0 1 ;;
 {% for i in range(8) %} ADD LR0 LR0 LR0 ;; {% endfor %}
 SET LR3 LR0 ; SET LR2 LR0 ;;
 ADDBI LRD2 4 ;;
 SET LR1 LR3 ; SET LR2 LR0 ;;
 {% for i in range(2) %} ADD LR0 LR0 LR0 ; ADD LR1 LR1 LR1 ;; {% endfor %}
 SET LR7 LR10 ;;
{% endmacro %}
 SET LR12 CR0 ; SET LR11 CR0 ; SET LR10 CR0 ;;
 SET LR9 CR0 ; SET LR0 CR0 ;;
batch:
 SET LR14 {{ cr.in0_d1 }} ; SET LR13 {{ start }} ;;
head:
 SET LR8 CR0 ; SET LR5 {{ k }} ;;
{% if n == 64 %}
 SET LR0 CR0 ;;
 {{ seed() }}
 BEQ LR7 CR0 panel64_seeded ;;
panel64_batch:
 ADDBI LRD0 1 ; DEC LR7 1 ; BNE LR7 CR1 panel64_batch ;;
panel64_seeded:
 SET LR7 CR0 ;;
panel64_k:
 LD.MULT R0 LR13 {{ cr.in1 }} ;;
 MULT.VE LR7 CR1 0 LR7 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;;
 {% for i in range(3) %}
 MULT.VE LR7 CR1 0 LR7 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ; ADDBI LRD0 32 ; ADDBI LRD2 8 ;;
 {% endfor %}
 SET LR6 LR13 ;;
 LD.MULT R0 LR6 {{ cr.in1 }} ; INC LR6 1 ;;
 MULT.VE LR7 CR1 0 LR7 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ; ADDBI LRD0 -96 ; ADDBI LRD2 8 ;;
 {% for i in range(3) %}
 MULT.VE LR7 CR1 0 LR7 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ; ADDBI LRD0 32 ; ADDBI LRD2 8 ;;
 {% endfor %}
 ACTIVATE.QUANTIZE identity {{ cr.ds }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR8 ;;
 ADDBI LRD0 -96 ; ADDBI LRD2 -56 ; INC LR8 1 ;;
 ADD LR13 LR13 {{ stride }} ; DEC LR5 1 ; BNE LR5 CR1 panel64_k ;;
{% else %}
panel_k:
 SET LR0 CR0 ; SUB LR6 LR13 CR1 ; SET LR4 {{ cr.n }} ;;
 {{ seed() }}
 BEQ LR7 CR0 panel_indices_ready ;;
panel_batch_index:
 ADDBI LRD0 1 ; DEC LR7 1 ; BNE LR7 CR1 panel_batch_index ;;
panel_indices_ready:
 SET LR7 CR0 ; SET LR9 CR0 ;;
 INC LR9 4 ;;
panel_source:
 LD.MULT R0 LR6 {{ cr.in1 }} ; INC LR6 1 ;;
 {% for i in range(4) %}
 MULT.VE LR7 CR1 0 LR7 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;;
 ADDBI LRD0 32 ; ADDBI LRD2 8 ; DEC LR4 8 ;;
 BEQ LR4 CR0 panel_store ;;
 {% endfor %}
 ADDBI LRD0 -128 ; DEC LR9 1 ; BNE LR9 CR1 panel_source ;;
 ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR8 ;;
 INC LR8 1 ; SET LR9 CR0 ;;
 INC LR9 4 ; ADDBI LRD2 -128 ; B panel_source ;;
panel_store:
 ACTIVATE.QUANTIZE identity {{ cr.ds }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR8 ;;
 INC LR8 1 ; ADD LR13 LR13 {{ stride }} ; DEC LR5 1 ; BNE LR5 CR1 panel_k ;;
{% endif %}
 {# LR13 advanced across k; the next head starts at that address. #}
 SET LR8 CR0 ; SET LR7 {{ tiles }} ; SET LR0 CR0 ;;
tile:
 SET LR2 LR12 ; SET LR6 {{ m }} ;;
row:
 LD.MULT R0 LR2 {{ cr.in0 }} ; SUB LR3 LR8 {{ tiles }} ; SET LR4 CR0 ; SET LR5 {{ k }} ;;
 DEC LR4 1 ;;
 LD.MULT.CYCLIC LR3 {{ cr.panel }} LR0 ; ADD LR3 LR3 {{ tiles }} ; DEC LR5 1 ;;
 MULT.RC.VE LR0 LR4 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR3 {{ cr.panel }} LR0 ; ADD LR3 LR3 {{ tiles }} ; INC LR4 1 ;;
 DEC LR5 1 ;;
reduce:
 MULT.RC.VE LR0 LR4 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR3 {{ cr.panel }} LR0 ; ADD LR3 LR3 {{ tiles }} ; INC LR4 1 ; DEC LR5 1 ; BNE LR5 CR1 reduce ;;
 MULT.RC.VE LR0 LR4 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 ;;
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ; ADD LR2 LR2 {{ cr.in0_d1 }} ; DEC LR6 1 ;;
 ADD LR11 LR11 {{ tiles }} ; BNE LR6 CR0 row ;;
 INC LR8 1 ; DEC LR7 1 ; BEQ LR7 CR1 tiles_done ;;
 SUB LR11 LR11 {{ m }} ;;
 SUB LR11 LR11 {{ m }} ;;
 INC LR11 1 ; B tile ;;
tiles_done:
 {% if n > 128 %} DEC LR11 1 ;; {% endif %}
 INC LR12 1 ; DEC LR14 1 ; BNE LR14 CR1 head ;;
 SUB LR12 LR2 {{ cr.in0_d1 }} ; INC LR10 1 ; SET LR8 CR0 ;;
 INC LR12 1 ;;
 DEC LR15 1 ; BNE LR15 CR1 batch ;;
 HALT ;;
