label cominit
   \ Turn on frame buffer
   0 3 devfunc
   a1 80 80 mreg   \ This bit must be on so you can talk to the Graphics registers below
   a7 08 08 mreg   \ This one too
   end-table

   \ Turn on I/O space access for display controller
   1 0 devfunc
   04 01 01 mreg
   end-table

   01 3c3 port-wb                    \ Graphics Chip IO port access on
   10 3c4 port-wb   01 3c5 port-wb   \ Graphics Chip register protection off

   \ The preceding setup was all so that we can write the following bit.
   \ It seems silly to have a bit that controls the UART in the graphics
   \ chip sequencer register block (additional editorializing elided...).

   78 3c4 port-wb   3c5 port-rb              \ Old value in al
   h# 80 # al or  al bl mov                  \ Set south module pad share enable
   78 3c4 port-wb   3c5 # dx mov  bl al mov  al dx out

   \ If the SERIAL_EN jumper is installed, or if the machine is an A-test,
   \ route the external pin to the UART; otherwise leave it connected to the VCP port.

   \ SERIAL_EN is not installed.  Determine the board ID.

   \ First we check for a cached board ID in CMOS RAM, to avoid the
   \ possibly time-consuming operation of asking the EC.

   \ To read the high half of CMOS RAM we must enable it
   d# 17 0 devfunc
   4e 18 18 mreg  \ Enable ports 74/75 for CMOS RAM access  - 10 res be like Phx
   end-table

   \ Configure the I/O decoding to enable access to the EC
   \ Do this outside the if..then so the setup is consistent in all cases
   d# 17 0 devfunc
   40 44 44 mreg  \ Enable I/O Recovery time (40), Enable ports 4d0/4d1 for edge/level setting (04)
   4c c0 40 mreg  \ Set I/O recovery time to 2 bus clocks
   59 ff 1c mreg  \ Keyboard (ports 60,64) and ports 62,66 on LPC bus (EC)
   5c ff 68 mreg  \ High byte (68) of PCS0
   5d ff 00 mreg  \ High byte (00) of PCS0
   64 0f 07 mreg  \ PCS0 size is 8 bytes - to include 68 and 6c
   66 01 01 mreg  \ PCS0 Enable
   67 10 10 mreg  \ PCS0 to LPC Bus
   end-table

   \ This delay is empirically necessary before reading CMOS - minimum is 36000 - about 50 ms
   \ Before the delay has elapsed, the CMOS RAM returns 0 instead of the stored value.
   d# 40000 wait-us

   \ As an optimization to avoid long waits for the EC to respond, read the board ID
   \ that is cached in CMOS RAM.  This might not in fact be an optimization in light
   \ of the above delay ...
   h# 83 # al mov  al h# 74 # out  h# 75 # al in    \ check byte - should be ~board-id
   al ah mov   ah not                               \ ~check byte in AH
   h# 82 # al mov  al h# 74 # out  h# 75 # al in    \ board-id in AL

   al ah cmp  0<>  if  \ If the check byte matches, fall through with the ID in AL

      \ If check byte is wrong, we have to ask the EC
   
      h# 6c # al in   \ EC status register
      2 # al and      \ input buffer full bit
      0<>  if         \ If the bit is nonzero, we can't send a command yet
         \ We don't wait for the EC; if it is busy we assume B-test
         \ It shouldn't be busy at this point because we haven't tried to talk to it yet
         h# d1 # al mov     \ EC busy - report B-test
      else
         h# 19 # al mov  al h# 6c # out   \ Send board ID command to EC
         d# 200 # cx mov    \ Wait up to 200 mS for the EC to respond
         begin
            d# 1000 wait-us \ 1 mS delay so we don't pound on the EC
            h# 6c # al in   \ Get status register
            3 # al and      \ Check for output buffer full
            1 # al cmp
         loopne
         <> if    \ Not equal means timeout
            h# d1 # al mov  \ EC timeout - report B-test
         else
            h# 68 # al in   \ Get board ID byte from EC
         then
      then
   then

   \ Now AL contains the board ID
   h# d1 # al cmp  u<  if
      acpi-io-base h# 4c + port-rl  h# 200000 bitclr  ax dx out  \ Turn off WLAN activity LED (GPIO10)

      \ A-test
      d# 17 0 devfunc
      9b 01 01 mreg  \ 1 selects GPO11/12 instead of CR_PWSEL/CR_PWOFF (DCONLOAD)
      46 c0 40 mreg  \ Enable UART on VCP port
      end-table

   else
      \ B-test or later
      acpi-io-base h# 4c + port-rl  h# 20000 bitset  ax dx out  \ Turn off WLAN activity LED (GPIO10)

      \ For B-test and later, we only enable serial if the jumper is present
      acpi-io-base 48 +  port-rb  h# 10 # al test  0=  if
         d# 17 0 devfunc
         46 c0 40 mreg  \ Enable UART on VCP port
         end-table
      then
   then

   d# 17 0 devfunc
   \ Standard COM2 and COM1 IRQ routing
   b2 ff 34 mreg

   \ For COM1 - 3f8 (ff below is 3f8 3 >> 80 or )

   b0 30 10 mreg
   b4 ff ff mreg   \ 3f8 3 >>  80 or  - com base port

   \ For COM2 - 2f8 (df below is 2f8 3 >> 80 or )
   \ b0 30 20 mreg
   \ b5 ff df mreg
   end-table

   init-com1   \ The usual setup dance for a PC UART...

   ret
end-code
