;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:    Main Purge Valve Timer Subroutine
;
;------------------------------------------------------------------------------

code

;------------------------------------------------------------------------------
; This turns a conditional relative branch into a 16-bit address jump
; It is used in 2 places by the routine below.
;------------------------------------------------------------------------------
.LEE3A          jmp         .LEF33

;------------------------------------------------------------------------------
;                        Main Purge Valve Timer Subroutine
;
; This subroutine is called, with the interrupt mask ON, from the coolant
; temperature service routine. But it is called only if X0085.4 is clear,
; which is set low by special end-of-list ADC control value. This routine
; sets 'purgeValveTimer' value and also sets the purge valve fault code.
;
; Note that values between zero and 40,000 are stored in the 'purgeValveTimer'
; variable. The value controls the purge valve as follows:
;       Below  4,000, purge valve is constant OFF
;       Above 29,000, purge valve is constant ON
;       Other values control pulsing of purge valve in microseconds.
;
;------------------------------------------------------------------------------

purgeValve      ldaa        $008D               ; load bits value
                anda        #$FE                ; clear X008D.0
                staa        $008D               ; store bits value
                ldaa        $0085               ; load another bits value X0085.7 (indicates no or low eng RPM)
                bmi         .LEE3A              ; test X0085.7 (eng running?, if set, NO, so branch up to jump down)

                ldaa        $0089               ; eng IS running
                anda        #$03                ; mask X0089.1 and X0089.0
                bne         .LEE3A              ; if X0089.1 or X0089.0 set, branch up to jump down

                ldaa        $00DC               ; load bits value
                bita        #$04                ; test X00DC.2 (controls 1-time code)
                bne         .LEE63              ; branch if bit is set

                oraa        #$04                ; set X00DC.2 (this is a block of 1-time code)
                staa        $00DC               ; store bits value
                ldaa        fuelTempCount       ; load EFT sensor count
                cmpa        #$55                ; compare with 85 decimal (48 C or 118 F)
                bcc         .LEE63              ; branch ahead if EFT is cooler than this
                ldd         $C145               ; data value is $2EE0 (12000 dec)
                std         $0098               ; reset down counter to 12000 dec


.LEE63          ldaa        coolantTempCount    ; load ECT sensor count
                cmpa        #$32                ; compare with $32 (51 C or 124 F)
                bcc         .LEEE3              ; branch ahead to jump if cooler than this
                
                ldaa        $008A               ; load bits value
                bita        #$40                ; test X008A.6 (0 = startup timeout)
                bne         .LEE87              ; branch ahead if not yet timed out

                                                ; after warmup, load X2022/23 and X2024/25 here
                ldaa        $201F               ; load bits value
                bita        #$02                ; test X201F.1 (controls 1-time loading of X2022/23 and X2024/25)
                bne         .LEE87
                
                oraa        #$02                ; set X201F.1 (1-time code control)
                staa        $201F
                ldd         $C202               ; value is $0C00 (3072 dec)
                std         $2024               ; init X2024 to 3072 dec
                ldd         $C140               ; value is $1482 (5250 dec)
                std         $2022               ; init X2022 to 5250 dec


.LEE87          ldaa        $0088               ; load bits value
                bita        #$02                ; test X0088.1 (road speed sensor fail bit)
                bne         .LEE93              ; branch ahead if VSS fail
                
                ldaa        $008B               ; load bits value
                bita        #$01                ; test X008B.0 (road speed GT 4 KPH)
                beq         .LEEA7              ; branch to jump if road speed > 4 KPH

.LEE93          ldd         engineRPM           ; load eng RPM
                subd        $C142               ; data value = $06B8 (1720 RPM)
                bcc         .LEEAA              ; branch ahead if RPM > 1720
                
                ldaa        $0086               ; load bits value
                bpl         .LEEA4              ; branch ahead if X0086.7 is zero
                
                ldaa        $0088               ; load bits value
                bita        #$10                ; test X0088.4 (set when eng RPM > 1250)
                bne         .LEF03              ; branch down if RPM > 1250

.LEEA4          jmp         .LEFC3              ; this 'jmp' is the only way to get to LEFC3
;---------------------------------------

.LEEA7          jmp         .LEF38              ; only used in 1 one place above
;---------------------------------------

.LEEAA          ldaa        fuelMapNumber       ; load fuel map number
                beq         .LEEB3              ; branch if fuel map 0
                
                cmpa        #$04                ; compare with 4
                bcs         .LEF25              ; branch down if fuel map 1, 2 or 3
                
;---------------------------------------
; For closed loop maps (0, 4 and 5)
;---------------------------------------

.LEEB3          ldd         $0098               ; load purge valve down counter
                subd        #$1000              ; subtract 4096
                bcc         .LEF25              ; if counter > 4096, branch down to load 40,000 into 'purgeValveTimer'
                
                ldaa        $00DD               ; load bits value
                bita        #$08                ; test X00DD.3
                beq         .LEF25              ; if 0, branch down to load 40,000 into 'purgeValveTimer'
                
                ldab        $0085               ; load bits value
                bitb        #$08                ; test X0085.3
                beq         .LEF21              ; if 0, branch to clr bits and load 40000 into 'purgeValveTimer'
                
                ldab        fuelMapLoadIdx      ; load the fuel map row pointer (range: $00 through $70)
IF BUILD_R3360_AND_LATER                
                cmpb        #$10                ; compare with $10 (late LR code)
ELSE
                cmpb        #$30                ; compare with $30 (older code including TVR)
ENDC                
                bcc         .LEF21              ; if greater, branch to clr bits and load 40000 into 'purgeValveTimer'
                
                ldab        ignPeriod           ; load ignition period
IF BUILD_R3360_AND_LATER
IF BUILD_R3652  ; cold weather chip
                cmpb        #$3A                ; this value unchanged for CWC
ELSE
                cmpb        #ignPeriodEngStart  ; value is $3A (500 RPM) (for late LR code)
ENDC                                
ELSE
                cmpb        #$0D                ; older code: $0D (2250 RPM)
ENDC                
                bcs         .LEF21              ; branch if RPM is lower, to clr bits and load 40,000

                ldab        $203C               ; X203C is a delay counter for setting purge valve fault code (88)
                bne         .LEF21              ; if counter not zero, branch to clr bits and load 40,000
                
                bita        #$10                ; test X00DD.4
                bne         .LEEE6              ; branch if not zero (this is the only path to LEEE6)
                
                oraa        #$10                ; set  X00DD.4
                staa        $00DD               ; store bits value
                ldab        #$FF                ; load $FF
                stab        $00DB               ; reset local counter to $FF

.LEEE3          jmp         .LEF33              ; one place (above) jumps to this
;---------------------------------------
                                                ; LEED9 (above is the only path here (X00DD is in A)
.LEEE6          ldab        $00DB               ; load local counter
                beq         .LEEF3              ; branch ahead if counter is zero
                
                decb                            ; else decrement it by 1
                stab        $00DB               ; store it
                bita        #$80                ; test X00DD.7
                bne         .LEF25              ; if one, branch down to load purge valve timer with 40,000
                bra         .LEF33              ; else it's zero, branch down to next section

.LEEF3          bita        #$80                ; test X00DD.7
                bne         .LEF05              ; branch ahead if bit is set
                
                oraa        #$80                ; set X00DD.7
                staa        $00DD               ; store it
                ldab        #$FF                ; load B with $FF
                stab        $00DB               ; reset local counter to $FF
                ldab        secondaryLambdaR    ; load left bank, battery backed value X0040 (MSB only)
                stab        $009A               ; and store it in X009A

.LEF03          bra         .LEF25              ; branch down
;---------------------------------------
                                                ; only jump is from LEEF5 above, X00DD is in A
.LEF05          ldab        secondaryLambdaR    ; load left bank, battery backed value X0040 (MSB only)
                subb        $009A               ; subtract X009A
                addb        $C22F               ; this data value is in the range of 1 to 3
                cmpb        $C230               ; this data value is in the range of 2 to 6
                bhi         .LEF17              ; branch ahead if B result if higher
                
                ldab        faultBits_4A
                orab        #$80                ; <-- Set Fault Code 88 (Purge Valve Fault)
                stab        faultBits_4A

.LEF17          anda        #$F7                ; clear X00DD.3
                ldab        $203B
                orab        #$01                ; set X203B.0 (this is the only bit used in this bits value)
                stab        $203B


.LEF21          anda        #$6F                ; clr X00DD.7 and X00DD.4
                staa        $00DD               ; store X00DD
;---------------------------------------
;       Turn Purge Valve ON
;---------------------------------------
.LEF25          ldd         #$9C40              ; $9C40 = 40,000 (this turns purge valve ON)
;---------------------------------------
                                                ; code falls thru or from 1 place below (LEF33)
.LEF28          std         purgeValveTimer
                jmp         .LEFE2              ; jump down to last block
;---------------------------------------
                                                ; there are 3 branches to here from below
.LEF2D          ldaa        $008D
                anda        #$8E                ; clr X008D bits 6,5,4,0
                staa        $008D
;---------------------------------------
;       Turn Purge Valve OFF
;
; There are a number of ways to get here
; Eng not running - jumps to here
;---------------------------------------

.LEF33          ldd         #$0000              ; set purge valve timer value to zero
                bra         .LEF28              ; branch up to store purgeValveTimer and jump down to last block
                
;---------------------------------------
; There is 1 jmp from above to get here
;---------------------------------------
                                                ; path to here is jmp (above) at LEEA7
.LEF38          ldaa        $0086
                bpl         .LEF33              ; branch ahead if X0086.7 is zero
                
                ldd         $0098               ; load down counter
                bne         .LEFB1              ; branch ahead if counter is not zero
                
                ldab        fuelMapNumber       ; load fuel map number
                beq         .LEF6E              ; branch down if fuel map is 0
                
                cmpb        #$04                ; compare with 4
                bcc         .LEF6E              ; branch to LEF6E if map is 4 or 5
                
;---------------------------------------
; For maps 1, 2 and 3
;---------------------------------------
                ldab        coolantTempCount    ; load ECT sensor count
                cmpb        $C17E               ; inside coolant temp table (value is $23 or 87 degrees C)
                bcc         .LEF2D              ; branch up if cooler than this
                
                ldab        $00DC
                bitb        #$08                ; test X00DC.3
                beq         .LEF2D              ; branch up if X00DC.3 is set
                
                ldab        $008D
                bitb        #$10                ; test X008D.4
                bne         .LEFA0              ; branch down if X008D.4 is set
                
                orab        #$10                ; set  X008D.4
                andb        #$7F                ; clr  X008D.7
                stab        $008D               ; store X008D
                ldd         engineRPM           ; load engine RPM
                std         $202D               ; store eng RPM at X002D/2E
                ldd         $C147               ; value is usually $0052
                std         $0098               ; reset down counter to this value
                bra         .LEFB1              ; branch down
                
;---------------------------------------
; For maps 0, 4 and 5 (purge valve timer code)
;
; It seems when 00E2.4 is set, purge valve
; is turned OFF by interrupt.
;---------------------------------------
.LEF6E          ldab        $0088               ; load X0088
                andb        #$60                ; mask X0088.6 and X0088.5
                cmpb        #$60                ; check both bits
                bne         .LEF2D              ; branch ahead if either bit is clear
                
                ldab        $008D               ; load X008D
                bitb        #$10                ; test X008D.4
                bne         .LEFA0              ; branch ahead if bit is set
                
                ldaa        $00E2               ; load X00E2
                anda        #$EE                ; clr X00E2.4 and X00E2.0
                staa        $00E2               ; store X00E2
                ldaa        secondaryLambdaR    ; load left bank value at X0040 (MSB only)
                staa        $009A               ; store it at X009A
                orab        #$10                ; set  X008D.4
                andb        #$7F                ; clr  X008D.7
                stab        $008D               ; store X008D
                ldd         $C147               ; value is usually $0052
                std         $0098               ; reset down counter to this value
                ldaa        $203B
                bita        #$01                ; test X203B.0
                bne         .LEFB1              ; branch down if bit is set
                
                ldaa        $00DD
                oraa        #$08                ; set X00DD.3
                staa        $00DD
                bra         .LEFB1              ; branch down
                
;---------------------------------------
.LEFA0          andb        #$EF                ; clr X008D.4
                orab        #$80                ; set X008D.7
                stab        $008D               ; store X008D
                ldaa        $0088
                anda        #$9F                ; clear X0088.6 and X0088.5
                staa        $0088
                ldd         $C145               ; value is $2EE0 (12000 dec)
                std         $0098               ; reset down counter to 12000 dec

.LEFB1          ldaa        $008D
                bita        #$80                ; test X008D.7
                bne         .LEFC0              ; branch down if bit is set
                
                ldx         #$C13F              ; load index with address of data value (value is $3C)
                oraa        #$01                ; set X008D.0
                staa        $008D               ; store X008D
                bra         .LEFCD              ; branch down

;---------------------------------------
.LEFC0          jmp         .LEF33              ; there are 2 references to this jump
;---------------------------------------
;    EEA4 is the only way to get here
;---------------------------------------

.LEFC3          ldd         engineRPM           ; load engine RPM
                subd        #$0320              ; subtract 800 dec
                bcs         .LEFC0              ; branch back to jmp if RPM < 800
                
                ldx         #$C13D              ; load index with address of data value (value is $C8)
;---------------------------------------
                                                ; can also branch here from LEFBE
.LEFCD          ldab        $00,x               ; load B (value will be 60 dec or 200 dec)
                ldaa        fuelMapLoadIdx      ; load A with fuel map row index
                mul                             ; multiply (highest possible value is $70 * $C8 = $5780)
                asld                            ; arithmetic doublw (highest value now $AF00)
                addd        $C140               ; add $1482 (highest now $C382 = 50,050 dec)
                std         purgeValveTimer     ; store in 'purgeValveTimer'
                subd        #$6D60              ; subtract 28000 (this is the constant ON threshold)
                bcs         .LEFE2              ; branch ahead to last block if value < 28000
                
                ldd         #$6D60              ; else limit value to 28000
                std         purgeValveTimer     ; and store it
;---------------------------------------
; Last code block
;
; LEFE2 is the only way out of this
; subroutine. Code falls through, branches
; from XEFDB or jumps from XEF2A
;
;---------------------------------------
.LEFE2          ldx         $2024               ; after warmup, X2024/25 is loaded with 3072 dec and decrements to zero in about 24 secs
                beq         .LF011              ; branch ahead when it reaches zero (takes about 23 to 28 seconds)
                
                dex                             ; decrement the 16-bit value at X2024/25
                stx         $2024               ; and store it
                ldd         purgeValveTimer     ; load 'purgeValveTimer'
                beq         .LEFFE              ; branch ahead if zero
                
                ldd         $2022               ; after warmup, X2022/23 is loaded with 5250 and increments to approx 16K to 18K
                subd        purgeValveTimer     ; subtract 'purgeValveTimer'
                bcc         .LF006              ; branch ahead if X2022/23 was greater than 'purgeValveTimer'
                
                ldd         $2022               ; 
                addd        $C200               ; value is $0004 (add this to X2022/23)
                bra         .LF00C              ; and branch ahead

.LEFFE          ldd         $C140               ; value is $1482 (5250 dec)
                std         $2022               ; set X2022/23 to this value
                bra         .LF011              ; and branch to end

.LF006          ldd         $2022               ; load X2022/23
                subd        $C200               ; value $0004, subtract this from X2022/23
.LF00C          std         $2022               ; store it
                std         purgeValveTimer     ; also store it as 'purgeValveTimer'
.LF011          ldaa        $0088
                anda        #$EF                ; clear X0088.4 (set when eng RPM > 1250)
                staa        $0088
                rts                             ; return, end of purge valve timer routine
code
