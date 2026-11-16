{% set nb = s1_n // 128 %}
{% set ke = [s0_vocab,8] | min %}
{# w1 is in [-2,2], in1 is exactly 1: truncated positional IDs <= 3. #}
{% set pe = [s4_vocab,4] | min %}
{% set selectors = cr.pos %}
{% set first = cr.out0 %}
{% macro op(kind='ADD',first=false,idx='LR0',scalar='CR1') -%}
MULT.VE {{ idx }} {{ scalar }} 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.{{kind}}{{'.FIRST' if first else ''}} ;;
{%- endmacro %}
{% macro st(row,activation='identity',tensor=cr.work) -%}
SET LR10 CR0 ;;
INC LR10 {{ row }} ;;
ACTIVATE.QUANTIZE {{activation}} {{ cr.qf }}.H {{ cr.qf }}.L {{tensor}} LR10 ;;
{%- endmacro %}
{% macro ld(row,reg='R0',tensor=cr.work) -%}
SET LR10 CR0 ;;
INC LR10 {{row}} ;;
LD.MULT {{reg}} LR10 {{tensor}} ;;
{%- endmacro %}
{% macro cyc(row,slot='LR0',tensor=cr.work) -%}
SET LR10 CR0 ;;
INC LR10 {{row}} ;;
LD.MULT.CYCLIC LR10 {{tensor}} {{slot}} ;;
{%- endmacro %}
    INC LR1 128 ; INC LR14 128 ; INC LR12 {{s0_tokens // 128}} ;;
    INC LR15 {{nb}} ;;
    LD.MULT R1 LR0 {{cr.work}} ;;
first_tokens:
    LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(ke) %}
{% for boundary in [k,k+1] %}
{{op('SUB',true,scalar=cr.sharp)}}
{% for j in range(boundary) %}
{{op('ADD',idx='LR1',scalar=cr.sharp)}}
{% endfor %}
{{st(1,'relu6')}}
{{cyc(1)}}
{{op('ADD',true,'LR1')}}
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
{{st(2 if boundary==k else 3,'relu')}}
{% endfor %}
{{cyc(2)}}
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{cyc(3)}}
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu {{cr.qf}}.H {{cr.qf}}.L {{selectors}} LR3 ;;
    INC LR3 1 ;;
{% endfor %}
    SET LR4 CR0 ;;
first_lane:
    SET LR5 CR0 ;;
first_channel:
    SET LR6 CR0 ; SET LR7 LR5 ;;
{% for k in range(ke) %}
    LD.MULT R0 LR6 {{selectors}} ;;
    LD.MULT.CYCLIC LR7 {{cr.w1}} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
    INC LR6 1 ; INC LR7 {{nb}} ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{first}} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR15 first_channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 first_lane ;;
    INC LR2 1 ; SET LR3 CR0 ;;
    BLT.S LR2 LR12 first_tokens ;;
    SET LR2 CR0 ; SET LR8 CR0 ; SET LR12 CR0 ;;
    SET LR13 CR0 ;;
    INC LR8 40 ;;
    INC LR12 {{s4_tokens //128}} ;;
{% for j in range(pe //255) %}
    INC LR13 255 ;;
{% endfor %}
    INC LR13 {{pe %255}} ;;
    SET LR15 CR0 ;;
    INC LR15 {{s5_n //128}} ;;
second_tokens:
    LD.MULT R0 LR2 {{first}} ;;
    LD.MULT.CYCLIC LR0 {{cr.in1}} LR0 ;;
{{op('ADD',true,scalar=cr.sharp)}}
    MULT.RC.VE LR0 {{cr.sharp}} 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
    # threshold zero covers -1 < x < 1 (integer conversion truncates).
{{op('ADD',idx='LR1',scalar=cr.sharp)}}
    SET LR3 CR0 ;;
    ACTIVATE.QUANTIZE relu6 {{cr.qf}}.H {{cr.qf}}.L {{cr.pos}} LR3 ;;
{{op('SUB',idx='LR1',scalar=cr.sharp)}}
{{op('ADD',idx='LR1')}}
    INC LR3 1 ;;
thresholds:
{{op('SUB',idx='LR1',scalar=cr.sharp)}}
    ACTIVATE.QUANTIZE relu6 {{cr.qf}}.H {{cr.qf}}.L {{cr.pos}} LR3 ;;
    INC LR3 1 ;;
    BLT.S LR3 LR13 thresholds ;;
{{op('SUB',idx='LR1',scalar=cr.sharp)}}
    ACTIVATE.QUANTIZE relu6 {{cr.qf}}.H {{cr.qf}}.L {{cr.pos}} LR3 ;;
    SET LR3 CR0 ; SET LR11 LR13 ;;
    INC LR11 1 ;;
clamp_threshold:
    LD.MULT.CYCLIC LR3 {{cr.pos}} LR0 ;;
{{op('ADD',true,'LR1')}}
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
{{st(1,'relu')}}
{{cyc(1)}}
{{op('ADD',true,'LR1')}}
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{cr.pos}} LR3 ;;
    INC LR3 1 ;;
    BLT.S LR3 LR11 clamp_threshold ;;
select_begin:
    SET LR3 CR0 ;;
make_selectors:
    LD.MULT.CYCLIC LR3 {{cr.pos}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    INC LR3 1 ;;
    LD.MULT.CYCLIC LR3 {{cr.pos}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
    DEC LR3 1 ;;
    ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{selectors}} LR3 ;;
    INC LR3 1 ;;
    BLT.S LR3 LR13 make_selectors ;;
    SET LR4 CR0 ;;
second_lane:
    SET LR5 CR0 ;;
second_channel:
    SET LR6 CR0 ; SET LR7 LR5 ;;
{{op('ADD',true,'LR1','CR0')}}
second_dot:
    LD.MULT R0 LR6 {{selectors}} ;;
    LD.MULT.CYCLIC LR7 {{cr.w5}} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
    INC LR6 1 ; INC LR7 {{s5_n //128}} ;;
    # merge494 uses the preceding embedding row for selector 494.
    SET LR10 CR0 ;;
    INC LR10 255 ;;
    INC LR10 239 ;;
    BEQ LR6 LR10 merge_weight ;;
    INC LR10 1 ;;
    BEQ LR6 LR10 restore_weight ;;
    BLT.S LR6 LR13 second_dot ;;
    BEQ LR0 LR0 second_store ;;
merge_weight:
    DEC LR7 {{s5_n //128}} ;;
    BEQ LR0 LR0 second_dot ;;
restore_weight:
    INC LR7 {{s5_n //128}} ;;
    BEQ LR0 LR0 second_dot ;;
second_store:
    ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{cr.work}} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR15 second_channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 second_lane ;;
    INC LR2 1 ;;
    BLT.S LR2 LR12 second_tokens ;;
    SET LR2 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
{% for j in range((s10_rows * nb)//255) %}
    INC LR12 255 ;;
{% endfor %}
    INC LR12 {{(s10_rows * nb)%255}} ;;
add_loop:
    LD.MULT R0 LR2 {{first}} ;;
    SET LR9 LR2 ;;
    INC LR9 40 ;;
    LD.MULT.CYCLIC LR9 {{cr.work}} LR0 ;;
{{op('ADD',true)}}
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{first}} LR2 ;;
    LD.MULT R0 LR2 {{first}} ;;
    LD.MULT.CYCLIC LR5 {{cr.table}} LR0 ;;
{{op('ADD',true)}}
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{first}} LR2 ;;
    INC LR2 1 ; INC LR5 1 ;;
    BLT.S LR5 LR15 add_no_wrap ;;
    SET LR5 CR0 ;;
add_no_wrap:
    BLT.S LR2 LR12 add_loop ;;
    # Row statistics in slots 0 (sum) and 1 (sum of squares).
    SET LR2 CR0 ; SET LR7 CR1 ; SET LR13 CR0 ;;
    INC LR13 {{nb}} ;;
    SET LR3 CR0 ; SET LR4 CR0 ;;
    INC LR3 128 ; INC LR4 128 ;;
    INC LR4 128 ;;
    SET LR14 LR4 ;;
    INC LR14 128 ;;
    LD.MULT R0 LR0 {{cr.work}} ;;
{{op('ADD',true)}}
{{op('ADD')}}
{{st(35,'reciprocal')}}
norm_row:
    SET LR5 LR2 ; SET LR6 LR2 ;;
    INC LR6 {{nb}} ;;
{{op('ADD',true,scalar='CR0')}}
stats:
    LD.MULT R0 LR5 {{first}} ;;
    LD.MULT.CYCLIC LR5 {{first}} LR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; AGG.SUM LR0 {{cr.qf}}.H ;;
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; AGG.SUM LR7 {{cr.qf}}.H ;;
    INC LR5 1 ;;
    BLT.S LR5 LR6 stats ;;
{{st(3)}}
{{ld(3)}}
{{op('SUB')}}
{{st(4)}}
    # Broadcast sum and sumsq hi/lo, multiply by exact reciprocal C.
{% for slot in [0,1] %}
    SET LR11 CR0 ;;
    INC LR11 {{slot}} ;;
{{ld(3)}}
    MULT.EE LR11 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{ld(4)}}
    MULT.EE LR11 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
{{st(5)}}
{{ld(5)}}
{{op('SUB')}}
{{st(6)}}
    LD.MULT.CYCLIC LR0 {{cr.c}} LR0 ;;
{{ld(5)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{ld(6)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
{{st(7+slot*2)}}
{{ld(7+slot*2)}}
{{op('SUB')}}
{{st(8+slot*2)}}
{% endfor %}
    # variance = E[x*x] - mean*mean + eps.
{{ld(9)}}
{{op('ADD',true)}}
{{ld(10)}}
{{op('ADD')}}
{{cyc(7)}}
{{ld(7)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
{{ld(8)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
{{cyc(8)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
    LD.MULT R0 LR0 {{cr.epsilon}} ;;
{{op('ADD')}}
{{st(11)}}
{{ld(11)}}
{{op('SUB')}}
{{st(12)}}
    # Recover variance before LUT, then Newton refine the rounded rstd.
{{ld(11)}}
{{op('ADD',true)}}
{{ld(12)}}
{{op('ADD')}}
{{st(13,'rsqrt')}}
{{cyc(13)}}
{{ld(13)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{st(14)}}
{{ld(14)}}
{{op('SUB')}}
{{st(15)}}
{{cyc(11)}}
{{ld(14)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{ld(15)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
{{cyc(12)}}
{{ld(14)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
{{st(16)}}
{{ld(16)}}
{{op('SUB')}}
{{st(17)}}
{{cyc(13)}}
{{ld(16)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{ld(17)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
{{st(18)}}
{{ld(18)}}
{{op('SUB')}}
{{st(19)}}
{{ld(13)}}
{{op('ADD',true)}}
{{cyc(35)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
{{ld(18)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
{{ld(19)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
{{st(20)}}
{{ld(20)}}
{{op('SUB')}}
{{st(21)}}
    SET LR5 LR2 ; SET LR11 CR0 ;;
norm_chunk:
    # Fold gamma into refined inverse std, retaining a residual.
    LD.MULT.CYCLIC LR11 {{cr.gamma}} LR0 ;;
{{ld(20)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{ld(21)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
{{st(22)}}
{{ld(22)}}
{{op('SUB')}}
{{st(23)}}
{{cyc(7,'LR3')}}
{{cyc(8,'LR4')}}
    LD.MULT.CYCLIC LR5 {{first}} LR0 ;;
{% for wr in [22,23] %}
{{ld(wr)}}
    MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if wr==22 else ''}} ;;
    MULT.RC.VV LR3 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
    MULT.RC.VV LR4 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
    LD.MULT R0 LR11 {{cr.beta}} ;;
{{op('ADD')}}
    ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{cr.out0}} LR5 ;;
    INC LR5 1 ; INC LR11 1 ;;
    BLT.S LR5 LR6 norm_chunk ;;
    SET LR2 LR6 ;;
    BLT.S LR2 LR12 norm_row ;;
    HALT ;;
