{# Scratch triples: x=0, polynomial=3, product=6, maximum=9,
   sum=12, inverse=15, correction=18, one=21; staging=24. #}
{% macro idx(n, r='LR1') %}
{% if n == 1 %}
    SET {{r}} CR1 ;;
{% else %}
    SET {{r}} CR0 ;;
{% if n %}
    INC {{r}} {{n}} ;;
{% endif %}
{% endif %}
{% endmacro %}
{% macro load(n, reg='R0', base=cr.tmp) %}
{{idx(n)}}
    LD.MULT {{reg}} LR1 {{base}} ;;
{% endmacro %}
{% macro cyc(n, base=cr.tmp) %}
{{idx(n)}}
    LD.MULT.CYCLIC LR1 {{base}} LR0 ;;
{% endmacro %}
{% macro store(n, act='identity', base=cr.tmp) %}
{{idx(n)}}
    ACTIVATE.QUANTIZE {{act}} CR15.L {{cr.qf}}.L {{base}} LR1 ;;
{% endmacro %}
{% macro split(n) %}
{% for i in range(3) %}
{{store(n+i)}}
{% if i<2 %}
    LD.MULT R0 LR1 {{cr.tmp}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro sum3(n, sign='ADD', first=true) %}
{% for i in range(3) %}
{{load(n+i)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{sign}}{{'.FIRST' if first and i==0 else ''}} ;;
{% endfor %}
{% endmacro %}
{% macro product(a,b, sign='ADD',first=true) %}
{% for i in range(3) %}
{{cyc(a+i)}}
{% for j in range(3) %}
{% if i+j<4 %}
{{load(b+j)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{sign}}{{'.FIRST' if first and i==0 and j==0 else ''}} ;;
{% endif %}
{% endfor %}
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ;;
    SET LR9 CR0 ;;
    INC LR9 {{probe + 121}} ;;
{{load(37,base=cr.coeff)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{split(21)}}
row:
{# Compute multiplied input exactly as two residual rows, and find a common shift. #}
{% for c in range(2) %}
    SET LR3 LR2 ;;
    INC LR3 {{c}} ;;
    LD.MULT.CYCLIC LR3 {{cr.in0}} LR0 ;;
    LD.MULT R0 LR0 {{cr.operand}} ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{split(30+c*3)}}
{% endfor %}
    MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for c in range(2) %}
{{load(30+c*3)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.MAX{{'.FIRST' if c==0 else ''}} LR0 CR15.L ;;
{% endfor %}
{{store(9)}}
    LD.MULT R0 LR1 {{cr.tmp}} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{store(9)}}
    SET LR4 CR0 ;;
exptile:
    SET LR3 CR0 ;;
    INC LR3 30 ;;
    ADD LR3 LR3 LR4 ;;
    ADD LR3 LR3 LR4 ;;
    ADD LR3 LR3 LR4 ;;
    LD.MULT R0 LR3 {{cr.tmp}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    INC LR3 1 ;;
    LD.MULT R0 LR3 {{cr.tmp}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    INC LR3 1 ;;
    LD.MULT R0 LR3 {{cr.tmp}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(9)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{split(0)}}
{{cyc(36,base=cr.coeff)}}
{% for i in range(3) %}
{{load(i)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 else ''}} ;;
{% endfor %}
{{split(0)}}
    SET LR5 CR0 ;;
    INC LR5 32 ;;
    SET LR3 LR5 ;;
    LD.MULT R0 LR3 {{cr.coeff}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for i in range(3) %}
    INC LR3 1 ;;
    LD.MULT R0 LR3 {{cr.coeff}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
{{split(3)}}
horner:
{{product(0,3)}}
    DEC LR5 4 ;;
    SET LR3 LR5 ;;
{% for i in range(4) %}
    LD.MULT R0 LR3 {{cr.coeff}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    INC LR3 1 ;;
{% endfor %}
{{split(3)}}
    BNE LR5 CR0 horner ;;
    SET LR5 CR0 ;;
    INC LR5 6 ;;
square:
{{product(3,3)}}
{{split(3)}}
    DEC LR5 1 ;;
    BNE LR5 CR0 square ;;
{% for i in range(3) %}
{{load(3+i)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    SET LR3 LR4 ;;
    ADD LR3 LR3 LR4 ;;
    ADD LR3 LR3 LR4 ;;
    INC LR3 {{i}} ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.exps}} LR3 ;;
{% endfor %}
    INC LR4 1 ;;
    BLT.S LR4 {{cr.K}} exptile ;;
{# Sum all six components into scalar lane 0. #}
    MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for i in range(6) %}
{{load(i,base=cr.exps)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
{% endfor %}
{{split(12)}}
{% for i in range(3) %}
{{load(12+i)}}
    MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 else ''}} ;;
{% endfor %}
{{split(12)}}
{{sum3(12)}}
{{store(15,'reciprocal')}}
{{load(15)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{split(15)}}
    SET LR5 CR0 ;;
    INC LR5 3 ;;
newton:
{{sum3(21)}}
{{product(12,15,'SUB',false)}}
{{split(18)}}
{{product(15,18)}}
{{sum3(15,first=false)}}
{{split(15)}}
    DEC LR5 1 ;;
    BNE LR5 CR0 newton ;;
{% for c in range(2) %}
{% for i in range(3) %}
{{load(c*3+i,base=cr.exps)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{store(i)}}
{% endfor %}
{{product(0,15)}}
{{split(3)}}
{% for i in range(3) %}
{{load(3+i)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    SET LR3 LR2 ;;
    ADD LR3 LR3 LR2 ;;
    ADD LR3 LR3 LR2 ;;
    INC LR3 {{c*3+i}} ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.probs}} LR3 ;;
{% endfor %}
{% endfor %}
    INC LR2 2 ;;
    BLT.S LR2 {{cr.M}} row ;;
{# Native RHS matrix product. #}
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    SET LR13 CR0 ;;
    INC LR13 {{[s2_m,128]|min}} ;;
{% if s2_m > 128 %}
    INC LR13 {{s2_m-128}} ;;
{% endif %}
matrow:
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 LR10 ;;
batch:
{% for side in range(2) %}
    SET LR8 LR7 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for chunk in range(2) %}
{% for comp in range(3) %}
    LD.MULT R0 LR8 {{cr.probs}} ;;
    SET LR3 LR6 ;;
{% if chunk %}
    INC LR3 128 ;;
{% endif %}
    SET LR14 CR0 ;;
dot{{side}}_{{chunk}}_{{comp}}:
    LD.MULT.CYCLIC LR3 {{cr.in1}} LR0 ;;
    MULT.RC.VE LR0 LR14 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    INC LR14 1 ; INC LR3 1 ;;
    BNE LR14 LR9 dot{{side}}_{{chunk}}_{{comp}} ;;
    INC LR8 1 ;;
{% endfor %}
{% endfor %}
{{split(24)}}
{% for i in range(3) %}
{{load(24+i)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{store(side*3+i,base=cr.result)}}
{% endfor %}
    INC LR6 128 ;;
    INC LR6 128 ;;
{% for i in range(6) %}
    ADD LR7 LR7 LR13 ;;
{% endfor %}
{% endfor %}
{% for i in range(3) %}
{% for side in range(2) %}
{{load(side*3+i,base=cr.result)}}
    SET LR4 CR0 ;;
    INC LR4 {{side*2}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.STRIDE 64 off on LR4 ;;
{% endfor %}
{{store(6+i*2,base=cr.result)}}
{% if i<2 %}
    LD.MULT R0 LR1 {{cr.result}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{store(7+i*2,base=cr.result)}}
{% endif %}
{% endfor %}
{% for i in range(5) %}
{{load(6+i,base=cr.result)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 else ''}} ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR11 ;;
    INC LR11 1 ; INC LR5 2 ;;
    SET LR14 CR0 ;;
    INC LR14 {{s2_b}} ;;
    BLT.S LR5 LR14 batch ;;
    INC LR10 6 ; INC LR12 1 ;;
    BLT.S LR12 LR13 matrow ;;
    HALT ;;
