\ See license at end of file
purpose: x86 real mode startup code.

command: &native &this
build-now

\ 386/486 processors begin executing at address ffff.fff0 in real mode
\ when they come out of reset.  Normally, that address would not be
\ accessable in real mode, but the processor does some magic things to
\ the Code Segment register so that the high order address lines are
\ "boosted" up to the ffff.xxxx range just after reset.  The "boosting"
\ persists until the CS register is modified (i.e. with a far jump).

\ The other segment register are not "boosted", so they can only access
\ the normal real mode range, essentially just the first megabyte.

\ The startup code must establish a Global Descriptor Table containing
\ suitable mappings, and then enter protected mode.  The space between
\ ffff.fff0 and the end of the ROM is insufficient to do this, so the
\ first few instructions must jump elsewhere, to a place where there
\ is enough room.

\ The code below is rather tricky, especially since the Forth assembler
\ always assumes 32-bit operand size and 32-bit addressing modes.
\ The code is executing in 16-bit mode, so the assembler must be used
\ carefully to ensure generation of the correct opcodes, and override
\ prefixes where necessary.


\needs start-assembling  fload ${BP}/cpu/x86/asmtools.fth
\needs write-dropin      fload ${BP}/forth/lib/mkdropin.fth
fload ${BP}/cpu/x86/pc/port80.fth

hex

start-assembling
hex

\ Addresses where the following items will be located in the processor's
\ physical address space:

\ ffff.fc00:  GDT  ( 4 active entries ) + padding
\ ffff.fc30:  Startup code plus padding
\ ffff.fff0:  Reset entry point - jump to startup code plus padding to end

\ Assembler macros for startup diagnostics

\ write a byte to an ISA port
: risa-c!   ( n a - )  "  # dx mov  # al mov   al dx out " evaluate  ;

: num>asc  ( al: b -- al: low ah: hi )
   " al ah mov " evaluate
   " h# f # al and " evaluate
   " h# 9 # al cmp  >  if h# 57 # al add  else  h# 30 # al add  then " evaluate

   " ah shr  ah shr  ah shr  ah shr " evaluate	\ shift down four bits
   " h# f # ah and " evaluate
   " h# 9 # ah cmp  >  if h# 57 # ah add  else  h# 30 # ah add then " evaluate

   " al bl mov  ah al mov  bl ah mov " evaluate
;

[ifdef] debug-reset
[else]
: report    ( char -- )  drop  ;
: reportc  ( -- )    ;
[then]

hex

\ odds for testing, evens for release
d# 8 constant loader-version#	\ monotonic
2 constant loader-format#	\ >1 when crc present

.( ROM loader: version# ) loader-version# .d
.( , format# )  loader-format#  .d cr

\ Real Mode Startup

hex

label rm-startup	\ Executes in real mode with 16-bit operand forms

   \ ffff.fc00	GDT

   2f   w,  ffff.fc00 l,	 0      w,  \ 0 Pointer to GDT in first slot
   0    w,  0         l,	 0      w,  \ * Null descriptor
   ffff w,  9b.000000 l,  00.c.f w,  \ 10 Code, linear=physical, full 4Gbytes
   ffff w,  93.000000 l,  00.c.f w,  \ 18 Data, linear=physical, full 4Gbytes
   ffff w,  9b.0f0000 l,  00.0.0 w,  \ 20 Code16, base f.0000, 64K
   ffff w,  93.0f0000 l,  00.0.0 w,  \ 28 Data16, base f.0000, 64K

   \ ------->>>>> Startup code, reached by branch from main entry point below
   \
   \ ffff.fc30

   here		\ Mark the beginning of this code so its size may be determined
		\ and so that a jump to it may be assembled later.

   16-bit

   h# 01 port80

   \ Invalidate TLB
   op: ax ax xor
   op: ax cr3 mov

[ifdef] init-com1      init-com1      [then]

[ifdef] debug-reset
carret report	 \ send it to com1 if you can...
linefeed report  \ send it to com1 if you can...
ascii F report	 \ send it to com1 if you can...
[then]

   \ The following instruction uses the CS: segment override because
   \ that segment is currently "boosted" up into the ROM space.
   \ It uses the operation size override to load a 32-bit pointer.
   \ The address override is not used; the GDT limit/address data structure
   \ above is reachable with a 16-bit address and through the "boosted"
   \ code segment.
      
   op: cs:  0f c, 01 c, 16 c, fc00 w,	\ lgdte  cs:[fc00]   Setup GDT

   op: cr0  bx  mov	\ Get existing CR0 value

   op: h# 7ffaffd1 # bx and  \ PG,AM,WP,NE,TS,EM,MP = 0
   op: h# 60000001 # bx or   \ CD, NW, PE = 1
\   1 #  bl  or		\ Set "protected mode" bit

   bx  cr0  mov		\ Enter protected mode
   eb c, 0 c,		\ jmp to next location to flush prefetch queue
                        \ note: CPL is now 0

   h# 03 port80


   \ We are in protected mode, but we are still executing from old
   \ 16-bit code segment, and will continue to do so until the far jump
   \ below

[ifdef] debug-reset
ascii o report
[then]

   \ set segment registers
   bx   bx  xor			\ Clear high byte
   18 # bl  mov			\ Data segment selector
   bx   ds  mov			\ Set segment register
   bx   es  mov			\ Set segment register
   bx   fs  mov			\ Set segment register
   bx   gs  mov			\ Set segment register

[ifdef] debug-reset
ascii r report
[then]

   bx   ss  mov			\ Set segment register

[ifdef] debug-reset
ascii t report
ascii h report
[then]

   h# 0f port80

   op: ad: ResetBase h# 10 #)  far jmp	\ Jump to Forth startup

   \ Pad the startup code so that the main entry point ends up at the
   \ correct address.

   here over -   ( adr , size-of-preceding-code )

   \ ffff.fc30 is the location of the code that follows the GDT
   ffff.fff0 ffff.fc30 - swap - ( address #bytes-to-pad )

   \ The code mustn't extend past ffff.ffc0, because that is where PC
   \ manufacturers put the 0x10-byte BIOS version string.
   dup h# 30 -  also forth 0< previous abort" Real mode startup code is too big"

   also forth  here over h# ff fill  previous	\ fill with FFs
   ( #bytes-to-pad ) allot	\ Pad out to ffff.fff0

   \ ------->>>>> Main Entry Point
   \ 
   \ ffff.fff0 - This is the hardwired address where the processor jumps
   \             when it comes out of reset

   16-bit
   cli cld		\ Turn off interrupts (does not affect NMI)
   #) jmp		\ Relative jump back to ffff.fc30
   0 w, 0 c,		\ align "pad" to end of ROM
   loader-version# l,	\ version#
   loader-format#  w,	\ "format" (>1 when crc present)
   ffff w,		\ placeholder for crc

end-code

end-assembling

writing rmstart.img
rm-startup here over - ofd @ fputs
ofd @ fclose

here rm-startup - constant /rm-startup
/rm-startup h# 400 <>  abort" Real mode startup code is not the right size"

\ LICENSE_BEGIN
\ Copyright (c) 2009 FirmWorks
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
