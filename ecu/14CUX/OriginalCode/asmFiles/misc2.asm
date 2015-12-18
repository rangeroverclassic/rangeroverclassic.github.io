;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       This file contains a number of miscellaneous routines.
;
; 
; 
; keepAlive
; LF0D5             (return timer value)
; indexIntoTable
; LF0FC
; LF119
; shiftEngDebugData
; LF135             (countdown timer 1)
; LF151             (countdown timer 2)
; LF171
; LF1AD
; LF1D4
; LF224
; absoluteValAB
; calcBatteryBackedChecksum
;
;------------------------------------------------------------------------------
code

;------------------------------------------------------------------------------
; Keep alive toggle
;
; This needs to be called periodically to keep the board from resetting.
;------------------------------------------------------------------------------
keepAlive       ldaa        port1data
                eora        #$80
                staa        port1data
                rts
                
;------------------------------------------------------------------------------
; Return Timer Value
;
;   This appears to be another routine that needs to be called periodically.
;   It's called from a number of places in the code and returns the 16-bit
;   timer value in the dual AB register.
;
;   The 16-bit counter (counterHigh/counterLow) is a free running counter
;   incremented by the Enable clock. The Enable is the external clock divided
;   by 4 (Frequency: 4 MHz/4 = 1 MHz). The overflow flag (TOF) is set when the
;   counter reaches 0xFFFF. This occurs every 65 milliseconds. Unlike other
;   code, the cli op-code is used before the sei op-code. The mask must be
;   cleared by other code eventually so that the ICI can again be triggered.
;   This actually looks like a coding error.
;
;   The routine increments X2001 and X00B2 every time the TOF is set (65 mSec).
;   X00B2 is used for measurement of the ICI period (for engine speed)
;   X2001 is used for periodic processing in the road speed routine
;
;   Note that reading CSR and then counterhigh will clear TOF
;
;------------------------------------------------------------------------------
LF0D5           cli                             ; clear interrupt mask
                nop
                nop                             ; (this area is different than older R2419 code)
                sei                             ; set interrupt mask
                ldaa        timerCSR
                bita        #$20                ; test timer overflow flag (TOF)
                beq         .LF0EE              ; branch ahead if no overflow

                inc         $2001               ; overflow, so increment both overflow counters
                bne         .LF0E7              ;
                dec         $2001               ;


.LF0E7          ldaa        $00B2               ;
                inca                            ;
                beq         .LF0EE              ;
                staa        $00B2               ;


.LF0EE          ldd         counterHigh         ; clear TOF and return counter value
                rts
                
;------------------------------------------------------------------------------
;
; Index Into Table
;
;   This is used often to select a column of data from a table based on a
;   comparison between a value (usually a temperature count) and the top row
;   of the table. The values passed in are:
;
;        X = Index to start of table
;        B = Number of columns in table
;        A = Value to compare (usually coolant temp count)
;
;   The routine increments the index in a loop and returns the updated index
;   when the table value exceeds the value in A (or when B becomes zero).
;
;------------------------------------------------------------------------------
indexIntoTable  cmpa        $01,x               ; subtract table value from coolant temp
                bcs         .indexingRet        ; return if result is LT zero
                decb                            ; decrement counter
                beq         .indexingRet        ; return if counter is zero
                inx                             ; increment index to next higher value in table
                bra         indexIntoTable
.indexingRet    rts

;------------------------------------------------------------------------------
; 
; This routine is called from two places in the ICI, right after the call to
; LF171 which is later in this file.
;
; Coming into this routine, AB is the value from either X0040/41 (left) or
; X0044/45 (right) minus $8000 (converted to abs value if needed). In other
; words, this is the delta from the $8000 neutral point.
;
; The index register (X) is preserved and used in this routine as a loop
; counter. The B accumulator is also preserved.
;
; XC0A0 is a code control value which is $80 for both R3526 and TVR code.
; Bit field 2:0 from this value is used to right shift the AB value in a
; loop. Since the X register will be either $0001 or $0002, the AB value will
; be reduced to 1/2 or 1/4.
;
; The bytes at XC0A0 is used as follows:
; XC0A0.7 = turns off fuel trim
; For code at F0FC, bits 2:0 are used
; For code at F119, bits 4:3 are used
;
;------------------------------------------------------------------------------
LF0FC           pshx                            ; push X
                pshb                            ; push B
                ldab        $C0A0               ; load code control byte ($80) into B
                andb        #$07                ; B is now zero
;-------------------------------------------------
; This is used by LF0FC (above) and LF119 (below)
; B accumulator comes in as zero from either path.
; The result is that AB will be reduced to either
; 1/2 or 1/4 of it's value.
;-------------------------------------------------
.LF103          addb        #$02                ; B is now #$02
                ldx         #$0000              ; clear index reg
                abx                             ; add B to X (X is now $0002)
                ldab        $008D               ; bits value
                bitb        #$71                ; test 4 bits in X008D (bits 6,5,4,0)
                pulb                            ; restore original AB value (does not affect zero flag)
                beq         .LF113              ; branch if all 4 bits are zero
                
                ldx         #$0001              ; X is now #$0001

.LF113          lsrd                            ; AB = AB/2
                dex
                bne         .LF113              ; loops once or twice
                
                pulx                            ; pull X
                rts                             ; return

;------------------------------------------------------------------------------
; 
; This routine is called from two places in the ICI.
;
; When entering, AB will be either left short term trim or right short term
; trim. X will be either $0040 or $0044. X is not used here but is preserved
; since it's used after the routine returns. Note that for each pass through
; the ICI, this routine is called twice for the same bank.
;
; When called for left bank:
;   AB = short term trim value X0065/66
;   X  = $0040 (value is at X0040/41)
;
; When called for right bank:
;   AB = short term trim value X0067/68
;   X  = $0044 (value is at X0044/45)
;
;
; The bytes at XC0A0 is used as follows:
; XC0A0.7 = turns off fuel trim
; For code at F0FC, bits 2:0 are used
; For code at F119, bits 4:3 are used
;
;------------------------------------------------------------------------------
LF119           pshx
                pshb
                ldab        $C0A0               ; this value is $80
                lsrb                            ; shift out bit 0
                lsrb                            ; shift out bit 1
                lsrb                            ; shift out bit 2
                andb        #$03                ; mask bits 4:3 (B is now zero)
                bra         .LF103

;------------------------------------------------------------------------------
; This code was used for development and can be deleted
;------------------------------------------------------------------------------
IF OBSOLETE_CODE
shiftEngDebugData  stab        $00C8
                   ldd         $00,x
                   tst         $00C8
                   beq         .LF134

.LF12E             asld
                   dec         $00C8
                   bne         .LF12E

.LF134             rts
ENDC

;------------------------------------------------------------------------------
;                          *** Countdown Timer 1 ***
;
; This routine is called from two places in the ICI. It's used to decrement the
; two following variables at a rate of approximately 1 Hz. The variable's
; address is passed into the routine in X (the index register).
;
; X009C - This is the value that's initialized from the 3rd row of the coolant
;         table. The initial value range is about $06 to $2D ($44 for TVR and
;         other markets).
;
; X2020 - This is an additional left bank specific value which is initialized
;         from the data value at XC1FF. This value is usually $03.
;
; Both of these value are used for temporary additional fuel at startup.
;
; The variable X0084 is used exclusively by this routine to maintain the timer
; and is comparable to X201E which is used in Countdown Timer 2 (below).
;
;------------------------------------------------------------------------------
LF135           ldaa        $0084               ; load timer maintenance variable
                ldab        ignPeriodFiltered   ; MSB is worth 512 uSec per count
                lsrb
                lsrb                            ; div by 4 (now 2.048 mSec/count)
                incb                            ; add 1 (an adjustment factor?)
                sba                             ; subtract B from A
                bcc         .LF14E              ; branch if result < X0084
                
                ldab        $0088
                eorb        #$08                ; toggle X0088.3
                stab        $0088
                bitb        #$08                ; test X201F.0
                beq         .LF14B              ; branch ahead every other time
                
                dec         $00,x               ; decrement indexed value (X009C or X2020)
.LF14B          ldaa        $C0F4               ; $96 for R3526, $FF for TVR

.LF14E          staa        $0084               ; store maintenance variable
                rts                             ; and return
                
;------------------------------------------------------------------------------
;                        *** Countdown Timer 2 ***
;
; This routine is called from two places in the ICI. It's used to decrement the
; two following variables at a rate of approximately 1 Hz. The variable's
; address is passed into the routine in X (the index register).
;
; X201D - This variable appears to prevent closed loop until it times out. It's
;         initialized from the value in XC1FE which is usually $10.
;
; X2021 - This is the right bank equivalent to X2020 mentioned in Timer 1 above.
;
; The variable X201E is used exclusively by this routine to maintain the timer
; and is comparable to X0084 which is used in Countdown Timer 1 (above).
;
;------------------------------------------------------------------------------
LF151           ldaa        $201E               ; load timer maintenance variable
                ldab        ignPeriodFiltered   ; MSB is worth 512 uSec per count
                lsrb
                lsrb                            ; div by 4 (now 2.048 mSec/count)
                incb                            ; add 1 (an adjustment factor?)
                sba                             ; subtract B from A
                bcc         .LF16D              ; branch if result < X201E
                
                ldab        $201F
                eorb        #$01                ; toggle X201F.0
                stab        $201F
                bitb        #$01                ; test X201F.0
                beq         .LF16A              ; branch ahead every other time
                
                dec         $00,x               ; decrement indexed value (X201D or X2021)
.LF16A          ldaa        $C0F4               ; $96 for R3526, $FF for TVR

.LF16D          staa        $201E               ; store maintenance variable
                rts                             ; and return
                
;------------------------------------------------------------------------------
; This subroutine is called from the code area in the ICI that deals with the
; long-term Lambda trim.
;
; There are two bank specific 16-bit values that are stored in the battery
; backed RAM area. They seem to loosely track the short term trim. It's not
; clear yet, which values control which.
;
;   X0040/41 = left bank
;   X0044/45 = right bank
;
; These values, like the trim values, have a neutral setting of $8000 and
; adjust up or down from there.
; 
; Coming into this routine, the 16-bit AB register is either of these values
; minus $8000 which means it will be a positive or negative number. The calling
; code knows the polarity and changes the negative number to it's absolute
; value. The passed in AB value is preserved by pushing to the stack and
; pulling before return.
;
;------------------------------------------------------------------------------
LF171           psha                            ; push MSB
                adda        #$02                ; add 2 to MSB ($0200 to value)
                cmpa        #$04                ; this checks to within 512 counts of both ends
                bhi         .LF1AB              ; if higher just branch to end and return
                
                ldaa        $0088               ; test bank indicator bit
                bmi         .LF184              ; branch ahead if right bank
;------------------
; Right Bank
;------------------
                ldaa        $0089               ; load bits value
                bita        #$10                ; test X0089.4
                beq         .LF1AB              ; if zero, branch to pull A and return
                bra         .LF18A              ; 
;------------------
; Left Bank
;------------------
.LF184          ldaa        $0089               ; load bits value
                bita        #$20                ; test X0089.5
                beq         .LF1AB              ; if zero, branch to pull A and return

.LF18A          pshb                            ; push B to stack
                tst         $0088               ; test bank indicator bit
                bmi         .LF19D              ; branch down if right bank
;------------------------------------------------
; Right Bank (subtract 1500 from short term trim)
;------------------------------------------------
                ldd         shortLambdaTrimR    ; $8000 (+/-)
                subd        $C7DB               ; for R3526, this value is 1500 decimal
                std         shortLambdaTrimR
                ldaa        $0088
                oraa        #$40                ; clear X0088.6
                bra         .LF1A8              ; branch to store, pull and return
;------------------------------------------------
; Left Bank (subtract 1500 from short term trim)
;------------------------------------------------
.LF19D          ldd         shortLambdaTrimL    ; $8000 (+/-)
                subd        $C7DB               ; for R3526, this value is 1500 decimal
                std         shortLambdaTrimL
                ldaa        $0088
                oraa        #$20                ; clear X0088.5

.LF1A8          staa        $0088               ; store bits value
                pulb                            ; pull B
.LF1AB          pula                            ; pull A
                rts                             ; return
                
;------------------------------------------------------------------------------
;
; This subroutine is called from 2 places in the ICI. Once from rich condition
; code and once from lean condition code.
;
; The passed in index value is:     rich condition  $0090
;                                   lean condition  $008E
;
; First, the signed counters at X0094 or X0095 are checked and, if zero, the
; routine simply returns.
;
; The bits value X00A8 is only used here. Just X00A8.7 and X00A8.0 are used.
;
;------------------------------------------------------------------------------
LF1AD           ldaa        $0088               ; test bank indicator bit
                bpl         .LF1BF              ; if 0088.7 is zero, branch to left side code
                
;------------------
; Right Bank
;------------------
                ldaa        $0095               ; right bank signed counter
                beq         .LF1D3              ; return if X0095 is zero
                inx                             ; rich: X0090, lean: X008E (increment to LSB of values)
                ldaa        $00A8               ; load bits value
                asra                            ; shift lsb into carry
                bcs         .LF1CD              ; branch if carry set (if X00A8.0 was 1)
                sec                             ; set carry
                rola                            ; rotate left (this restores the original value)
                bra         .LF1CF              ; branch to mask all unused bits in X00A8 and return
;------------------
; Left Bank
;------------------
.LF1BF          ldaa        $0094               ; left bank signed counter
                beq         .LF1D3              ; return if X0094 is zero
                ldaa        $00A8               ; load bits value
                bmi         .LF1CB              ; branch ahead if X00A8.7 is set
                oraa        #$80                ; set X00A8.7
                bra         .LF1CF              ; branch to mask all unused bits in X00A8 and return

.LF1CB          anda        #$01                ; clear X00A8.7

.LF1CD          inc         $00,x               ; increment indexed value
;----------------------------
; Mask unused bits and return
;----------------------------
.LF1CF          anda        #$81
                staa        $00A8
.LF1D3          rts

;------------------------------------------------------------------------------
; Update X00A9/AA (left) or X00AB/AC (right)
; (called from 2 places in ICI)
;------------------------------------------------------------------------------
LF1D4           ldd         mafDirectHi
                addd        mafDirectLo
                tst         $0088               ; test bank indicator bit
                bpl         .LF1E5              ; branch ahead if left bank
;-------------------------------------
                inc         $0095               ; right bank
                addd        $00AB
                std         $00AB
                rts
;-------------------------------------
.LF1E5          inc         $0094               ; left bank
                addd        $00A9
                std         $00A9
                rts
                
;------------------------------------------------------------------------------
; This code is unused and is here for the sake of byte-for-byte test builds.
; Some labels were added for proper disassembly.
;------------------------------------------------------------------------------
;maybeUnused5:
                bcs         .LF21D
                bra         .LF221
;maybeUnused6:
                ldab        $0072
                bpl         .LF1FE
                andb        #$7F
                aba
                bcc         .LF207
                ldaa        #$FF
                bra         .LF207

.LF1FE          ldab        #$80
                subb        $0072
                sba
                bcc         .LF207
                ldaa        #$00

.LF207          ldab        $004F
                bpl         .LF214
                andb        #$7F
                aba
                bcc         .LF21D
                ldaa        #$FF
                bra         .LF21D

.LF214          ldab        #$80
                subb        $004F
                sba
                bcc         .LF21D
                ldaa        #$00

.LF21D          suba        $00AD
                bcc         .LF223

.LF221          ldaa        #$01

.LF223          rts

;------------------------------------------------------------------------------
; Decrements value in X00BD, if not zero (called from 2 places in ICI)
;------------------------------------------------------------------------------
LF224           ldaa        $00BD
                beq         .LF22B
                deca
                staa        $00BD
.LF22B          rts

;------------------------------------------------------------------------------
; Returns absolute value of 16-bit negative number in AB
;------------------------------------------------------------------------------
absoluteValAB   coma
                comb
                addd        #$0001
                rts

;------------------------------------------------------------------------------
; Sums values from battery backed RAM and returns the result in A.
; This is used during startup and during shutdown (Inertia Switch routine).
;------------------------------------------------------------------------------
calcBatteryBackedChecksum   ldx         #batteryBackedRAM
                            ldaa        $00,x

.startChecksumCalcLoop      inx
                            cpx         #ramChecksum
                            beq         .doneWithChecksumCalc
                            adda        $00,x
                            bra         .startChecksumCalcLoop

.doneWithChecksumCalc       rts

;------------------------------------------------------------------------------
code
