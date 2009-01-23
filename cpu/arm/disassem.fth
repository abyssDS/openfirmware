purpose: ARM disassembler - prefix syntax
\ See license at end of file

vocabulary disassembler
also disassembler also definitions

headerless

variable instruction
variable end-found
variable display-offset  0 display-offset !
headers
variable dis-pc
: (pc@ ( -- adr ) dis-pc @ ;
defer dis-pc@ ' (pc@ is dis-pc@
: (pc! ( adr -- ) dis-pc ! ;
defer dis-pc!  ' (pc! is dis-pc!
: pc@l@ ( -- opcode ) dis-pc @ l@ ;
headerless

defer regs

string-array (real-regs
," r0"   ," r1"   ," r2"    ," r3"
," r4"   ," r5"   ," r6"    ," r7"
," r8"   ," r9"   ," r10"   ," r11"
," r12"  ," r13"  ," link"  ," pc"
end-string-array
: real-regs  ['] (real-regs is regs  ;

string-array (forth-regs
," r0"   ," r1"   ," r2"    ," r3"
," r4"   ," r5"   ," r6"    ," r7"
," r8"   ," up"   ," tos"   ," rp"
," ip"   ," sp"   ," lr"    ," pc"
end-string-array
: forth-regs  ['] (forth-regs is regs  ;
forth-regs

: udis. ( n -- )
   push-hex
   <#
   u# u# u# u# u# u# u# u#
   u#>  type   pop-base
;
' udis.  is showaddr

: +offset  ( adr -- adr' )  display-offset @  -  ;
: >mask  ( #bits -- mask )  1 swap << 1-  ;
: bits  ( right-bit #bits -- field )
   instruction @ rot >>   ( #bits shifted-instruction )
   swap >mask  and        ( field )
;
: 4bits  ( right-bit -- field )  4 bits  ;
: bit?  ( bit# -- f )  instruction @ 1 rot lshift and  0<>  ;
\ Extracts an index from the field "bit# #bits", indexes into the string
\ "adr len", which is assumed to contain substrings of length /entry,
\ and types the indexed substring.
: .fld  ( bit# #bits adr len /entry -- )
   >r drop  >r            ( bit# #bits r: /entry adr )
   bits                   ( index r: /entry adr )
   r> swap r@ * +  r>     ( adr' /entry )
   type
;

\ Display formatting
variable start-column
: op-col  ( -- )  start-column @  d# 8 +  to-column  ;

: .reg  ( bit# -- )  4bits regs ".  ;
: {<cond>}  ( -- )
   d# 28 4bits  d# 14 =  if  exit  then
   d# 28 4 " eqnecsccmiplvsvchilsgeltgtle  nv" 2 .fld
;

: .,  ( -- )  ." , "  ;
: .[  ( -- )  ." ["  ;
: .]  ( -- )  ." ]"  ;

: .rm  ( -- )      0 .reg  ;
: .rs  ( -- )      8 .reg  ;
: .rd,  ( -- )  d# 12 .reg  ., ;
: op.rd,  ( -- )  op-col  .rd,  ;
: .rb  ( -- )  d# 16 .reg  ;
alias .rn .rb

: .rm,shift  ( -- )
   .rm
   d# 4 8 bits  if   \ LSL #0 is no-shift; this isn't it
      .,
      4 8 bits  6 =  if  ." rrx"  exit  then
      5 2 " lsllsrasrror" 3 .fld  ."  "
      4 bit?  if  .rs  else  ." #" 7 5 bits .d  then
   then
;

: u.h  ( n -- )  dup  d# 9 u>  if  ." 0x"  then  (u.) type  ;
: ror  ( n cnt -- )  2dup d# 32 swap - lshift  -rot rshift or  ;
: .imm  ( -- )  0 8 bits  8 4bits  2*  ror u.h  ;

: ?.bit  ( adr len bit# -- )  bit?  if  type  else  2drop  then  ;

d# 20 constant d#20
d# 21 constant d#21
d# 22 constant d#22
d# 23 constant d#23
d# 24 constant d#24
d# 25 constant d#25

: {s}  ( -- )  " s"  d#20 ?.bit  ;
: {!}  ( -- )  " !"  d#21 ?.bit  ;
: {^}  ( -- )  " ^"  d#22 ?.bit  ;
: {b}  ( -- )  " b"  d#22 ?.bit  ;
: +/-  ( -- )  d#23 bit?  0=  if  ." -"  then  ;

: .r/imm  ( -- )
   d#25 bit?  if  ." #" .imm  else  .rm,shift  then
;
\ Indicates the form of the instruction that affects both PC and CPSR/SPSR
: {p}  ( -- )
   d#23 2 bits 3  =  if				\ MOV class
      d# 12 4bits h# f  =  if  ." p"  then	\ Rd is PC
   then
;
: .alu  ( -- )
   d#21 4  " andeorsubrsbaddadcsbcrsctstteqcmpcmnorrmovbicmvn"  3 .fld
   {<cond>}
;
: alu#  ( -- n )  d#21 4bits  ;
\ control instruction extension space
\ exceptions are encoded as tests with no setting of the condition codes
\                                OOIo oooS Rn/b   Rd   Rs shft   Rm
\                                00I1 0oo0
\ BX{<cond>}  Rm            cond 0001 0010  SBO  SBO  SBO 0001   Rm
\ MSR{<cond>} xPSR, y       cond 00x1 0R10 fsxc  SBO yyyy yyyy yyyy
\ MRS{<cond>} Rd, xPSR      cond 0001 0R00  SBO   Rd            SBZ

: .psr  ( -- )  d#22 bit?  if  ." s"  else  ." c"  then  ." psr"  ;
: .fields  ( -- )
   ." _"  " cxsf" drop  d# 16 4bits   ( adr mask )
   4  0  do  dup 1 and  if  over i + c@ emit  then  2/  loop
   2drop
;
: .mrs/sr  ( -- )
    d#21 bit?  if	\ MSR
       ." msr" {<cond>}
       op-col  .psr .fields ., .r/imm
    else		\ MRS
       ." mrs" {<cond>}  op.rd, .psr
    then
;
: .special  ( -- )
   instruction @ h# 026f.fff0 and  h# 002f.ff10 =  if
      ." bx" {<cond>}  op-col .rm
      exit
   then
   .mrs/sr
;

\ Arithmetic instruction extension space
: .alu-ext  ( -- )
   d#23 bit?  if	\ 64-bit multiply
      d#21 2  " umullumlalsmullsmlal"  5 .fld {<cond>} {s}
      op-col .rn ., .rd, .rs ., .rm
   else			\ 32-bit multiply
      d#21 2  " mulmla??????"          3 .fld {<cond>} {s}
      op-col .rb ., .rm ., .rs
      instruction @ h# 00200000 and  if  ., d# 12 .reg  then
   then
;
: w-bit  ( -- flag )  d#21 bit?  ;
: p-bit  ( -- flag )  d#24 bit?  ;

\ LD/ST extension space
\ SWP{<cond>} Rd, Rm, [Rn]           cond 0001 00ZZ   Rn   Rd  SBZ 1001   Rm
\ LDR{<cond>}{H|SH|SB} Rd, Rm, [Rn]  cond 000P UBW1   Rn   Rd addr 1SH1 addr
\ STR{<cond>}{H|SH|SB} Rd, Rm, [Rn]  cond 000P UBW0   Rn   Rd addr 1SH1 addr
: imm8  ( -- n )  8 4bits 4 lshift  0 4bits or  ;
: ,.r/imm8  ( -- )
    d#22 bit?  if
       imm8  if  .,  ." #" +/- imm8 u.h  then
    else
       ., +/- .rm
    then
;
: .ld/st  ( -- )  d#20 bit?  if  ." ld"  else  ." st"  then  ;
: .ldx  ( -- )
   .ld/st ." r" {<cond>}  " s" 6 ?.bit  " h" 5 ?.bit
    op.rd,
    .[ .rn  p-bit  if  ,.r/imm8 .] {!}  else  .] ,.r/imm8  then
;
: .swp  ( -- )  ." swp"  {<cond>}  " b" d#22 ?.bit  op.rd, .rm ., .[ .rn .]  ;

: .ld/st-ext  ( -- )  5 2 bits  if  .ldx  else  .swp  then  ;

: .ext  ( -- )		\ Extension space
   d#24 bit? 0=  5 2 bits 0=  and  if  .alu-ext  else  .ld/st-ext  then
;

\ Stop after changing PC
: ?pc-change  ( -- )  d# 12 4bits d# 15 =  end-found !  ;

: .alu-op  ( -- )	\ d# 25 3 bits 0|1 =
   d#25 bit? 0=  d# 4 bit? and  d# 7 bit? and  if  .ext  exit  then
   alu#  h# d and h# d =  if			\ Moves
      .alu {s}  op.rd, .r/imm
      ?pc-change
      exit
   then
   d#23 2 bits  2 =  if				\ Compares
      d#20 bit? 0=  if  .special exit  then
      .alu  op-col .rn ., .r/imm
      exit
   then
   .alu {s}  op.rd, .rn ., .r/imm
;
: .swi  ( -- )  ." swi"  op-col 0 d#24 bits u.h  ;

\ XXX handle muls they have 9 in the 4 4bits field, swp is one of them
\ : ^     ( -- ) 00400000 op-or ; \ ldm stm  PSR or force user-mode registers
\ : #     ( -- ) 02000000 op-or ; \ last operand is immediate
\ : s     ( -- ) 00100000 op-or ; \ flags are set according to result
\ : t     ( -- ) 00200000 op-or ; \ ldr str  force -T pin
\ : byte  ( -- ) 00400000 op-or ; \ ldr str operate bytewide

: .mregs  ( -- )
   ." {"                         ( )
   0 d# 16 bits   false          ( n need,? )
   d# 16  0  do                  ( n need,? )
      over 1 and  if             ( n need,? )
         if  ." , "  then  true  ( n need,?' )
         i regs ".               ( n need,? )
      then                       ( n need,? )
      swap 2/ swap               ( n need,?' )
   loop                          ( n need,?' )
   2drop                         ( )
   ." }"                         ( )
;
: .inc  ( -- )  d#23 2 " daiadbib" 2 .fld  ;
: .ldm/stm  ( -- )   \ d# 25 3 bits 4 =
   .ld/st  ." m" {<cond>} .inc
   op-col  .rb {!} ., .mregs  {^}
   d# 15 bit?  d# 20 bit? and  end-found !	\ Stop after PC change
;
: {t}  ( -- )  p-bit 0=  w-bit and  if  ." t"  then  ;
: imm12  ( -- n )  0 d# 12 bits  ;
: ,.addr-mode  ( -- )
   d#25 bit?  if
      ., +/- .rm,shift
   else
      imm12  if  ., ." #" +/- imm12 u.h  then
   then
;
: .ldr/str  ( -- )   \ d# 25 3 bits 2|3 =
   0 d# 28 bits  h# 0e00.0010 and  h# 0600.0010 =  if
      ." undefined" {<cond>}
      exit
   then
   .ld/st  ." r"  {<cond>} {b}  {t}
   op.rd, .[ .rb
   p-bit  if  ,.addr-mode .] {!}  else  .] ,.addr-mode  then
   ?pc-change
;
: .branch  ( -- )	\ d# 25 3 bits 5 =
   ." b"  " l" d#24 ?.bit  {<cond>}
   d#24 bit?  end-found !
   
   op-col dis-pc@ 8 +  0 d#24 bits  8 << 6 >>a +  +offset showaddr
;

: n.d  ( n -- )  push-decimal  <# u#s u#> type  pop-base   ;
: .creg  ( bit# -- )  4bits ." cr" n.d  ;
[ifdef] dis-fp
: .ldf/stf  ( -- )	 \ d# 25 3 bits 6 =
   .ld/st ." f"  ???
;
: .flt  ( -- )   \ d# 25 3 bits 7 =
   d#20 2 " fltfixwfsrfs" 3 .fld  op-col  .precision
;
XXX decode floating opcodes:
 0 8  fops  adf mvf muf mnf suf abs rsf rnd
 8 8  fops  dvf sqt rdf log pow lgn rpw exp
10 8  fops  rmf sin fml cos fdv tan frd asn
18 4  fops  pol acs ??? atn
[then]
: p#  ( -- n )  8 4bits  ;
: .p#,  ( n -- )  ." p" p# n.d  .,  ;
: .offset8  ( -- )  ." #" +/-  0 8 bits 4 *  u.h  ;
: .ldc/stc  ( -- )
   .ld/st ." c" {<cond>} " l" d#22 ?.bit
   op-col .p#,  d# 12 .creg .,  .[ .rn
   p-bit  if  ., .offset8 .] {!}  else  .] ., .offset8  then
;
: .cptail  ( -- )  d# 16 .creg ., 0 .creg ., 5 3 bits n.d  ;

\ Decode I/D Branch-Target/Write-Buffer Flush/Clean /Entry bits
\ for ARM4 Cache and TLB control registers
: .flushes  ( -- )
   7 bit?  if
      6 bit?  if
         ." Flush Branch Target"
      else
         0 bit?  if  ." Flush Prefetch"  else  ." Drain Write"  then
         ."  Buffer"
      then
   else
      " Clean " 3 ?.bit  " Flush " 2 ?.bit  " I" 0 ?.bit  " D" 1 ?.bit
   then
   "  entry" 5 ?.bit
;
: .clocks  ( -- )  \ For SA-110
   5 bit?  if
      0 4bits  case
      1 of  ." Enable odd word loading of Icache LFSR" cr  endof
      2 of  ." Enable even word loading of Icache LFSR" cr  endof
      4 of  ." Clear Icache LFSR"  endof
      8 of  ." Move LFSR to R14.Abort"  endof
      endcase
   else
      0 4bits  case
      1 of  ." Enable clock switching"  endof
      2 of  ." Disable clock switching"  endof
      4 of  ." Disable nMCLK output"  endof
      8 of  ." Wait for interrupt"  endof
      endcase
   then
;
string-array scc-regs
   ," ID"
   ," Control"
   ," TTBase"
   ," Domain"
   ," ?"
   ," FaultStatus"
   ," FaultAddress"
   ," Cache"
   ," TLB"
   ," ?"
   ," ?"
   ," ?"
   ," ?"
   ," ?"
   ," ?"
   ," Test/Clock/Idle"	\ SA-110
end-string-array
: .scc  ( -- )	\ Decode ARM4 system control coprocessor register ops
   \ Opcode1 should be 0
   ." p15(SCC), 0, " .rd,
   d# 16 .creg ." ("  d# 16 4 bits  dup scc-regs ".  ." )"  ( cr# )
   dup  7 8 between  if  drop ., .flushes exit  then
   d# 15  =  if  .clocks  then  \ SA-110
;
: .coproc  ( -- )
   p-bit  if  .swi exit  then
   d# 4 bit?  if		\ MRC and MCR
      d# 20 1 " mcrmrc" 3 .fld {<cond>} 
      op-col
      p# d# 15 =  if		\ System Control Coprocessor
         .scc
      else
         .p#,  d# 21 3 bits n.d .,  .rd, .cptail
      then
   else				\ CDP
      ." cdp" {<cond>}
      op-col  .p#,  d# 20 4bits  n.d .,   d# 12 .creg ., .cptail
   then
;

create classes
   ['] .alu-op  compile,  \ 0
   ['] .alu-op  compile,  \ 1  (immediate)
   ['] .ldr/str compile,  \ 2
   ['] .ldr/str compile,  \ 3  (immediate)
   ['] .ldm/stm compile,  \ 4
   ['] .branch  compile,  \ 5
   ['] .ldc/stc compile,  \ 6
   ['] .coproc  compile,  \ 7

: disasm  ( x -- )
   push-hex
   instruction !
   classes  d#25 3 bits ta+  token@ execute
   pop-base
;

headers
forth definitions
alias disasm disasm
: dis1  ( -- )
   ??cr
   dis-pc@ +offset  showaddr ." : "  pc@l@ udis.  ."   "
   #out @  start-column !
   pc@l@ disasm  cr
   /l dis-pc@ + dis-pc!
;
: +dis  ( -- )
   end-found off
   begin   dis1  end-found @  exit? or  until
;
: dis  ( adr -- )  dis-pc! +dis  ;

headerless
alias (dis dis
headers

previous previous definitions

\ LICENSE_BEGIN
\ Copyright (c) 1997 FirmWorks
\
\ Permission is hereby granted, free of charge, to any person obtaining
\ a copy of this software and associated documentation files (the
\ "Software"), to deal in the Software without restriction, including
\ without limitation the rights to use, copy, modify, merge, publish,
\ distribute, sublicense, and/or sell copies of the Software, and to
\ permit persons to whom the Software is furnished to do so, subject to
\ the following conditions:
\
\ The above copyright notice and this permission notice shall be
\ included in all copies or substantial portions of the Software.
\
\ THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
\ EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
\ MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
\ NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
\ LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
\ OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
\ WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
\
\ LICENSE_END