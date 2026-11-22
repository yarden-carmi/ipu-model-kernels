{% macro product(src, op) %}
    LD.MULT.CYCLIC LR5 {{cr.coeff}} LR0 ;;
    MULT.RC.VE LR0 {{src}} 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.{{op}} ; INC LR5 1 ;;
{% endmacro %}

{% macro contract(label, limit, split=false) %}
    MULT.VE LR0 CR0 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ; SET LR6 CR0 ;;
{{label}}:
{% for piece in range(2) %}
{% if split %}
    LD.MULT.CYCLIC LR5 {{cr.coeff}} LR0 ;;
    MULT.RC.VE LR0 LR6 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ;;
    MULT.RC.VE LR0 LR10 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ; INC LR5 1 ;;
{% else %}
{{product('LR6', 'ADD')}}
{% endif %}
{% endfor %}
    INC LR6 1 ;;
{% if split %}    INC LR10 1 ;;
{% endif %}
    BLT.S LR6 {{limit}} {{label}} ;;
    {# The store leaves R_ACC intact: subtract the rounded high row and save its residual. #}
    ACTIVATE.QUANTIZE identity {{cr.full}}.L {{cr.qf_in0}}.L {{cr.tmp}} LR7 ;;
    LD.MULT.CYCLIC LR7 {{cr.tmp}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.SUB ; INC LR7 1 ;;
    ACTIVATE.QUANTIZE identity {{cr.full}}.L {{cr.qf_in0}}.L {{cr.tmp}} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}

{% macro phase(b, c, d) %}
    SET LR7 CR0 ; SET LR5 LR11 ;;
{{product('CR1', 'ADD.FIRST')}}
{{product('CR1', 'ADD')}}
{% for op in ['ADD', b, c, d] %}
{% set mode = loop.index %}
{% for piece in range(2) %}
    LD.MULT.CYCLIC LR7 {{cr.tmp}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.{{op}} ; INC LR7 {{3 if mode == 3 and piece == 1 else 1}} ;;
{% endfor %}
{% endfor %}
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR8 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 {{cr.height}} ; SET LR9 {{cr.out0_d3}} ;;
row:
    SET LR3 {{cr.in0_d3}} ;;
site:
    LD.MULT R0 LR1 {{cr.in0}} ; SET LR5 CR0 ; SET LR7 CR0 ;;
{{contract('dc', cr.cin)}}
{{contract('horizontal', cr.cin)}}
{{contract('vertical', cr.cin)}}
{{contract('project', cr.cin)}}
    SET LR7 CR0 ;;
    INC LR7 6 ;;
    LD.MULT R0 LR7 {{cr.tmp}} ; SET LR10 CR0 ;;
    INC LR7 1 ;;
    LD.MULT R1 LR7 {{cr.tmp}} ; INC LR10 128 ;;
    INC LR7 1 ;;
{{contract('diagonal', cr.rank, true)}}
    SET LR8 LR2 ; SET LR11 LR5 ;;
{{phase('ADD', 'ADD', 'ADD')}}
    INC LR8 1 ;;
{{phase('SUB', 'ADD', 'SUB')}}
    ADD LR8 LR2 LR9 ;;
{{phase('ADD', 'SUB', 'SUB')}}
    INC LR8 1 ;;
{{phase('SUB', 'SUB', 'ADD')}}
    INC LR1 1 ; INC LR2 2 ; DEC LR3 1 ;;
    BNE LR3 CR0 site ;;
    ADD LR2 LR2 LR9 ; DEC LR4 1 ;;
    BNE LR4 CR0 row ;;
    HALT ;;
