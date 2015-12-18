;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013  Initial file.
;              26-Mar-2014  Updated comments.
;
;
;   Description:
;       Cold startup fuel injector chattering routine (below zero F)
;
;   This routine is called from the main loop (just before the ADC reading)
;   if bit X0085.7 is set (indicating low engine RPM or cranking condition).
;   The two injector bank controllers are opposite polarities.
;
;   This code is responsible for chattering or buzzing the injectors on very
;   cold start-up, probably to improve fuel atomization.
;
;   Port 1.2   Timer 3 - Even (left) Injector Bank (uses T4 transistor)
;   Port 2.1   Timer 1 - Odd  (right) Injector Bank (uses T2 transistor)
;
;   The Output Compare Flag (OCF) is set when the output compare reg matches
;   the free running counter.
;
;   When chattering, there are 11 pulses of approx 2.5 ms each (period is
;   about 5 msec). X00A6 is set to 20 by the ICI and is decremented here.
;
;   Note that it seems like the testing of the bank indicator bit (X0088.7)
;   is reversed. This is because the bank toggle bit is toggled in the ICI
;   after the bank fueling is set up. Also, fueling does alternate bank to
;   bank. There is no simultaneous startup fueling as indicated in the
;   documentation.
;
;   The MPU timers (exc. timer 2) are assigned as follows:
;
;   X0088.7   Bank       MPU Pin  Port  Timer  Transistor 40-Pin  Polarity
;   -----------------------------------------------------------------------
;     1     Right(even)     9     2.1     1       T2        13    Same(NAND)
;     0     Left (odd)     15     1.2     3       T4        11    Reversed
;
;   
;   The Output Compare Flag is set when the Output Compare Register for that
;   counter matches the free-running counter.
;
;------------------------------------------------------------------------------

code
LF04D           ldaa        timerStsReg
                tst         $0088
                bmi         .LF05D              ; test bank indicator bit
;-------------------------------
; Left Bank Code (X0088.7 = 0)
;-------------------------------
                bita        #$20                ; test Output Compare Flag 3
                beq         .LF0A0              ; return if low (injector still closed)
                
                ldd         #$04FB              ; load two 8-bit mask values (bit 2)
                bra         .LF064              ; branch to common bank code
;-------------------------------
; Right Bank Code (X0088.7 = 1)
;-------------------------------
.LF05D          bita        #$08                ; test Output Compare Flag 1
                beq         .LF0A0              ; return if low (injector still closed)

                ldd         #$FE01              ; load two 8-bit mask values (bit 0)
;-------------------
; Common Bank Code (Injector Bank was recently fired)
;-------------------
.LF064          std         $00C8               ; store mask values in 00C8/C9
                ldab        $00A6               ; this counter is set to 20 dec when temp is colder than zero F
                beq         .LF0A0              ; return if counter is zero
                decb                            ; decrement the counter
                stab        $00A6               ; and store it
                ldaa        timerCntrlReg1      ;
                tst         $0088               ; test bank indicator bit
                bmi         .LF0A1              ; branch ahead if X0088.7 is set (left bank)
;-------------------------------------------------------------------------------
;       *** Even (Left) Bank Cold Start Fuel Buzzing (port P12) ***
; Used when cranking under zero F or colder conditions.
; (The two bank controllers appear to be opposite polarities)
;-------------------------------------------------------------------------------
                lsrb                            ; A= timerCntrlReg1, B= 00A6 cntr, 00C8/C9= $04FB
                                                ; test cntr lsb here (clr 1st time)
                bcc         .LF07B              ; branch ahead if the lsb was zero
                
                oraa        $00C8               ; set OLVL3 (P12 = even injector bank) (injector off??)
                bra         .LF07D

.LF07B          anda        $00C9               ; lsb= 1, clr OLVL3 (even side off??)

.LF07D          oraa        #$01                ; set OLVL1 (to ensure only 1 bank is ON??)
                staa        timerCntrlReg1
                ldd         ocr3high            ; load output compare reg 3
                addd        compedFuelingVal    ; <-- ADD COMPENSATED FUELING VALUE

                                                ; *** Start Loop ***
.LF085          cmpa        timerStsReg         ; part of resetting routine?
                std         ocr3high            ; store new value in ocr3
                subd        #$0578              ; subtract 1400 dec
                std         ocr1High            ; store in ocr1
                jsr         LF0D5               ; update timers (returns 16-bit counter in A-B)
                subd        ocr3high
                subd        #$4000
                bcc         .LF0A0              ; <-- return here
                jsr         LF0D5               ; update timers (returns 16-bit counter in A-B)
                addd        #$0096
                bra         .LF085              ; *** End Loop ***

.LF0A0          rts

;-------------------------------------------------------------------------------
;          *** Odd (Right) Bank Cold Start Buzzing (port P21) ***
; Used when cranking under zero F or colder conditions.
; (The two bank controllers appear to be opposite polarities)
;-------------------------------------------------------------------------------

.LF0A1          lsrb                            ; B is 00A6 counter, A is timerCntrlReg1, 00C8/C9 = $FE01
                bcc         .LF0A8              ; branch ahead if the lsb was zero
                anda        $00C8               ; clr OLVL1 (P21 = odd injector bank)
                bra         .LF0AA

.LF0A8          oraa        $00C9               ; cntr lsb was one, 00C9=$FB, set bit 0 (output level 1)

.LF0AA          anda        #$FB                ; clr bit 2 (output level 3) (to ensure only 1 bank is ON)
                staa        timerCntrlReg1
                ldd         ocr1High            ; load output compare reg 1
                addd        compedFuelingVal    ; <-- ADD COMPENSATED FUELING VALUE

                                                ; *** Start Loop ***
.LF0B2          cmpa        timerStsReg         ; part of resetting routine?
                std         ocr1High            ; store new value in ocr1
                subd        #$0578              ; subtract 1400 dec
                std         ocr3high            ; store it in ocr3
                jsr         LF0D5               ; update timers (returns 16-bit counter in A-B)
                subd        ocr1High
                subd        #$4000
                bcc         .LF0A0              ; <-- return here
                jsr         LF0D5               ; update timers (returns 16-bit counter in A-B)
                addd        #$0096
                bra         .LF0B2              ; *** End Loop ***
                
                rts                             ; unused rts
code
