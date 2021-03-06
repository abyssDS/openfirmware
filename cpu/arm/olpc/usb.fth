\ See license at end of file
purpose: USB features common to most OLPC ARM platforms

0 0  " d4208000"  " /" begin-package  \ USB Host Controller
   h# 200 constant /regs
   my-address my-space /regs reg
   : my-map-in  ( len -- adr )
      my-space swap  " map-in" $call-parent  h# 100 +  ( adr )
   ;
   : my-map-out  ( adr len -- )  swap h# 100 - swap " map-out" $call-parent  ;
   " USBPHYCLK" " clock-names" string-property
   " /pmua" encode-phandle 5 encode-int encode+ " clocks" property
   d# 44 " interrupts" integer-property

   usb-hub-reset-gpio# 1  " usb-hub-reset-gpios" gpio-property

   " host" " dr_mode"  string-property
   " utmi" " phy_type" string-property

   " /usb2-phy" encode-phandle " transceiver" property

   false constant has-dbgp-regs?
   false constant needs-dummy-qh?
   : grab-controller  ( config-adr -- error? )  drop false  ;
   fload ${BP}/dev/usb2/hcd/ehci/loadpkg.fth

   " marvell,pxau2o-ehci" +compatible
   " u2o" " reg-names" string-property

\  false to delay?  \ No need for a polling delay on this platform
   : otg-set-host-mode  3 h# a8 ehci-reg!  ;  \ Force host mode
   ' otg-set-host-mode to set-host-mode

   : sleep  ( -- )  true to first-open?  ;
   : wake  ( -- )  ;
end-package

defer usb-power-on  ' noop to usb-power-on
defer reset-usb-hub ' noop to reset-usb-hub

: init-usb  ( -- )
   h# 9 h# 5c pmua!  \ Enable clock to USB block
   reset-usb-hub
   " /usb2-phy" " init" execute-device-method drop
;

stand-init: Init USB Phy
\  usb-power-on   \ The EC now controls the USB power
   init-usb
;

d# 350 config-int usb-delay  \ Milliseconds to wait before probing hub ports

\ Like $show-devs, but ignores pagination keystrokes
: $nopage-show-devs  ( nodename$ -- )
   ['] exit? behavior >r  ['] false to exit?
   $show-devs
   r> to exit?
;

\ Restrict selftest to external USB ports 1,2,3
\ dev /  3 " usb-test-ports" integer-property  dend

: (probe-usb2)  ( -- )
   " device_type" get-property  if  exit  then
[ifdef] use-usb-debug-port
   \ I haven't figured out how to turn on the EHCI cleanly
   \ when the Debug Port is running
   dbgp-off
[then]
   get-encoded-string  " ehci" $=  if
      pwd$ open-dev  ?dup  if  close-dev  then
   then
;
: (show-usb2)  ( -- )
   " device_type" get-property  if  exit  then
   get-encoded-string  " ehci" $=  if
      pwd$ $nopage-show-devs
   then
;

true value first-usb-probe?
: (silent-probe-usb)  ( -- )  " /" ['] (probe-usb2) scan-subtree  ;
: silent-probe-usb  ( -- )
   (silent-probe-usb)
   report-disk report-net report-keyboard
;
: probe-usb  ( -- )
   first-usb-probe?  if
      false to first-usb-probe?
      \ Initial probe to awaken the hub
      (silent-probe-usb)
      \ A little delay to let slow devices like USB scanner wake up
      d# 150 ms
   then
   silent-probe-usb

   ." USB devices:" cr
   " /" ['] (show-usb2) scan-subtree

;
alias p2 probe-usb

0 value usb-keyboard-ih
0 value otg-keyboard-ih

: attach-usb-keyboard  ( -- )
   " usb-keyboard" expand-alias  if   ( devspec$ )
      drop " /usb"  comp  0=  if      ( )
         " usb-keyboard" open-dev to usb-keyboard-ih
         usb-keyboard-ih add-input
      then
   else                               ( devspec$ )
      2drop
   then

   " otg/keyboard" expand-alias  if   ( devspec$ )
      open-dev to otg-keyboard-ih
      otg-keyboard-ih add-input
   else
      2drop
   then
;

: detach-usb-keyboard  ( -- )
   usb-keyboard-ih  if
      usb-keyboard-ih remove-input
      usb-keyboard-ih close-dev
      0 to usb-keyboard-ih
   then
;

: ?usb-keyboard  ( -- )
   attach-usb-keyboard
;

: usb-quiet  ( -- )
   detach-usb-keyboard
   " /usb@f0003000" " reset-usb" execute-device-method drop
   " /usb@d4208000" " reset-usb" execute-device-method drop
;

: suspend-usb  ( -- )
   detach-usb-keyboard
   " /usb" " sleep" execute-device-method drop
;
: has-children?   ( devspec$ -- flag )
   locate-device  if  false  else  child 0<>  then
;
: any-usb-devices?  ( -- flag )  " /usb/hub" has-children?  ;
: resume-usb  ( -- )
   init-usb
   " /usb" " wake" execute-device-method drop
   any-usb-devices?  if
      d# 2000 ms  \ USB misses devices if you probe too soon
   then
   silent-probe-usb
   attach-usb-keyboard
;

\ Unlink every node whose phys.hi component matches port
: port-match?  ( port -- flag )
   get-unit  if  drop false exit  then
   get-encoded-int =
;
: rm-usb-children  ( port -- )
   device-context? 0=  if  drop exit  then
   also                             ( port )
   'child                           ( port prev )
   first-child  begin while         ( port prev )
      over port-match?  if          ( port prev )
         'peer link@  over link!    ( port prev )      \ Disconnect
      else                          ( port prev )
         drop 'peer                 ( port prev' )
      then                          ( port prev )
   next-child  repeat               ( port prev )
   2drop                            ( )
   previous definitions
;

\ LICENSE_BEGIN
\ Copyright (c) 2010 FirmWorks
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
