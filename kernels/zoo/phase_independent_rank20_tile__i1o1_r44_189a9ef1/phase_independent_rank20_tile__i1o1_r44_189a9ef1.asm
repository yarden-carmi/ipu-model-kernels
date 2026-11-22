{% macro mac(ptr, src, op='ADD', residual=false) %}
    LD.MULT.CYCLIC {{ptr}} {{cr.coeff}} LR0 ;;
    MULT.RC.VE LR0 {{src}} 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.{{op}} ; INC {{ptr}} 1 ;;
{% if residual %}
    MULT.RC.VE LR0 LR10 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ;;
{% endif %}
{% endmacro %}

{% macro contract(label, limit, residual=false) %}
{{label}}:
{% for part in range(2) %}
{{ mac('LR5', 'LR6', residual=residual) }}
{% endfor %}
    INC LR6 1 {% if residual %}; INC LR10 1{% endif %} ;;
    BLT.S LR6 {{limit}} {{label}} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 {{cr.height}} ;;
row:
    SET LR3 {{cr.in0_d3}} ;;
site:
    SET LR5 CR0 ; SET LR8 LR2 ; SET LR11 CR0 ;;
    INC LR5 2 ; INC LR11 {{kh}} ;;
phase_row:
    SET LR9 CR0 ; SET LR13 LR8 ;;
    INC LR9 {{kw}} ;;
phase:
    LD.MULT R0 LR1 {{cr.in0}} ; SET LR6 CR0 ; SET LR7 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ;;
{{ contract('project', cr.cin) }}
    ACTIVATE.QUANTIZE identity {{cr.full}}.L {{cr.qf_in0}}.L {{cr.tmp}} LR7 ;;
    LD.MULT.CYCLIC LR7 {{cr.tmp}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.SUB ; INC LR7 1 ;;
    ACTIVATE.QUANTIZE identity {{cr.full}}.L {{cr.qf_in0}}.L {{cr.tmp}} LR7 ;;
    LD.MULT R1 LR7 {{cr.tmp}} ; SET LR6 CR0 ; SET LR10 CR0 ; SET LR14 CR0 ;;
    LD.MULT R0 LR0 {{cr.tmp}} ; INC LR10 128 ;;
{{ mac('LR14', 'CR1', 'ADD.FIRST') }}
{{ mac('LR14', 'CR1') }}
{{ contract('expand', cr.rank, true) }}
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.outds}}.L {{cr.qf_out0}}.L {{cr.out0}} LR13 ; DEC LR9 1 ;;
    BNE LR9 CR0 phase ; INC LR13 1 ;;
    ADD LR8 LR8 {{cr.out0_d3}} ; DEC LR11 1 ;;
    BNE LR11 CR0 phase_row ;;
    INC LR1 1 ; INC LR2 {{kw}} ; DEC LR3 1 ;;
    BNE LR3 CR0 site ;;
    ADD LR2 LR2 {{cr.row_skip}} ; DEC LR4 1 ;;
    BNE LR4 CR0 row ;;
    HALT ;;
