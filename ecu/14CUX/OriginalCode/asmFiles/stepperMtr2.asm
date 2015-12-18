;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       This group of subroutines appear to be later additions to the software.
;   In the original code, they can be found near the end of the code section
;   but before the serial port service routine. Most or all have to do with
;   the IACV or stepper motor in some way.
;
;------------------------------------------------------------------------------

code

;------------------------------------------------------------------------------
;                   A Stepper Motor Related Routine
;
;   This routine is called from the main loop. X204B/4C is a 16-bit value
;   which is initialized to 50 decimal and only used in the following two
;   routines.
;
;------------------------------------------------------------------------------
LF5F0           ldaa        $0086               ; load bits value
                bita        #$80                ; test X0086.7 (set and clrd in TPS routine)
                beq         .LF600              ; branch ahead if bit 7 is zero

                ldaa        $008B               ; 0086.7 is one
                bita        #$01                ; test X008B.0 (1 = road speed > 4 KPH)
                bne         .LF600              ; branch if road speed > 4 K{H
                
                ldaa        #$FF                ; load $FF into A 
                bra         .LF610              ; return

.LF600          ldaa        $2047               ; X0086.7 is zero
                anda        #$FE                ; clr X2047.0
                staa        $2047
                ldd         $C240               ; data value is $0032 (50 decimal)
                std         $204B               ; store in X204B/4C
                ldaa        #$00                ; load $00 into A
.LF610          rts                             ; return

;------------------------------------------------------------------------------
;                  Another Stepper Motor Related Routine
;
;   This is called from the main loop and is used to set X2047.3
;
;   Eng Spd < 1670 RPM -- resets 16-bit value at $204B/4C to 50 decimal
;   Eng Spd > 1670 RPM -- subtracts 1 from value this value each time and
;                           when zero, sets X2047.3
;
;------------------------------------------------------------------------------
LF611           ldd         ignPeriod           ; load ignition period
                subd        $C253               ; data value is $118B (1670 RPM)
                bcs         .LF620              ; branch if eng spd is > 1670 RPM

                                                ; <-- eng spd is < 1670 RPM
                ldd         $C240               ; data value is $0032 (50 dec)
                std         $204B               ; reset $204B/4C to 50
                bra         .LF639              ; return

.LF620          ldd         $204B               ; <-- eng spd is > 1670 RPM
                subd        #$0001              ; decrement $204B/4C
                std         $204B               ; store value
                bne         .LF639              ;  return if not zero
                
                ldd         $C240               ; when $204B/4C gets to zero,
                std         $204B               ; reset X204B/4C to 50
                ldaa        $2047
                oraa        #$08                ; and set X2047.3
                staa        $2047
.LF639          rts                             ; return

;------------------------------------------------------------------------------
;                       Set Stepper Motor to close by 30 Steps
;
;   Called from main loop.
;
;   When X2047.3 is clr: (just return)
;   When X2047.3 is set:
;       If iacMotorStepCount is not zero, (just return)
;       Else: Set X008A.0, reset iacMotorStepCount to 30, clr X2047.3
;
;------------------------------------------------------------------------------
LF63A           ldab        $2047
                bitb        #$08                ; test X2047.3
                beq         .LF657              ; return if bit 3 is zero
                
                ldaa        iacMotorStepCount   ; abs value of stepper mtr adjustment
                bne         .LF657              ; return if iacMotorStepCount is not zero
                
                sei                             ; set interrupt mask
                ldaa        $008A
                oraa        #$01                ; set X008A.0 (stepper mtr direction bit, 1 = close)
                staa        $008A
                ldaa        $C23F               ; data value is $1E (30 decimal)
                staa        iacMotorStepCount   ; store as stepper motor asjustment
                andb        #$F7                ; clr X2047.3
                stab        $2047
                cli                             ; clear interrupt mask
.LF657          rts                             ; return

;------------------------------------------------------------------------------
;               Yet Another Stepper Motor Related Routine
;
;   This is called from the idleControl subroutine in idleControl.asm
;
;------------------------------------------------------------------------------
LF658           ldaa        coolantTempCount    ; load ECT sensor count
                cmpa        $C247               ; data value is $22 or $23 (about 88 deg C)
                bcs         .LF677              ; branch way down if coolant temp is hotter than this
                
                ldab        $2048               ; value at X2048 starts at $80 and varies up or down
                bmi         .LF679              ; branch ahead if X2048 is > $7F (bit 7 set)
;----------------------------
; X2048 is less than 128
;----------------------------
                ldaa        #$80                ; load A with 128
                sba                             ; subtract X2048 from 128 (result will be positive)
                tab                             ; transfer A to B
                ldaa        $0072               ; load A with value from X0072
                sba                             ; subtract B (delta) from A (X0072)
                bcs         .LF6E9              ; branch to rts if delta was greater
                
                cmpa        #$80                ; compare A with $80
                bcc         .LF6E9              ; branch to rts if A is >= $80
                
                cmpa        $C261               ; data value is $53
                bcc         .LF689              ; branch ahead if A is >= $53
                rts                             ; return
                
;----------------------------
.LF677          bra         .LF6EA              ; this serves as a 2-step branch from above
;----------------------------
; X2048 is greater than 128
;----------------------------
.LF679          subb        #$80                ; subtract $80 from value (result will be zero or positive)
                ldaa        $0072               ; load A with value from X0072
                aba                             ; add them
                bcs         .LF6E9              ; branch to rts if carry is set (value overflowed)
                
                cmpa        #$80                ; compare result with $80
                bhi         .LF6E9              ; branch to rts if result is > $80
                cmpa        $C261               ; data value is $53
                bcs         .LF6E9              ; branch to rts if result is >= $53

.LF689          clra                            ; clear A
                ldab        $00AD               ; can be discrete values 0, 5, 26 and 31
                std         $00C8               ; store value $00xx in X00C8/C9
                ldab        $006E               ; value based on coolant temp (range 100 to 160)
                std         $00CA               ; store value $00xx in X00CA/CB
                ldd         $2053               ; a 16-bit value ($8000 +/-)
                addd        $00C8               ; 
                bcs         .LF6CD
                
                subd        $00CA
                bcs         .LF6C9
                
                std         $00C8
                ldaa        $004F               ; battery backed value (typically 108 decimal)
                bpl         .LF6AF
                
                anda        #$7F
                staa        $00CB
                ldd         $00C8
                subd        $00CA
                bcs         .LF6C9
                
                bra         .LF6BB

.LF6AF          ldaa        #$80
                suba        $004F
                staa        $00CB
                ldd         $00C8
                addd        $00CA
                bcs         .LF6CD

.LF6BB          bmi         .LF6C9

                std         $00C8
                ldd         #$8000
                subd        $00C8
                tsta
                bne         .LF6CD
                
                bra         .LF6CF

.LF6C9          ldab        #$00
                bra         .LF6CF

.LF6CD          ldab        #$FF

.LF6CF          ldaa        #$80                ; load A with $80
                sba                             ; subtract B from A
                bcc         .LF6D5
                clra

.LF6D5          cmpa        $C261               ; for R3526, value is $53
                bcc         .LF6DD
                ldaa        $C261               ; for R3526, value is $53

.LF6DD          staa        $0072               ; 1 of 3 non $80 writes (stayed 128 exc for spike to 37 at RR end)
                ldaa        $2047
                anda        #$BF                ; clr 2047.6
                staa        $2047
                bra         .LF742

.LF6E9          rts
;------------------------------------------------------------------------------
                                                ; code above branches here if coolant temp is hotter than 88 deg C
.LF6EA          ldaa        $0087
                bita        #$02                ; test 0087.1 (indicates air flow sensor fault)
                bne         .LF6F7
                
                ldaa        fuelMapLoadIdx      ; load the fuel map row (load) index
                cmpa        $C243               ; compare with XC243 (for R3526, value is $20)
                bcc         .LF6E9              ; return is row index is > $20

.LF6F7          ldaa        coolantTempCount    ; load the ECT value
                cmpa        $C246               ; for R3526, value is $1C (94 deg C)
                bcs         .LF6E9              ; return if ECT is hotter than this
                
                cmpa        $C247               ; for R3526, value is $22 (88 deg C)
                bcc         .LF6E9              ; rtn if ECT is cooler than this
                
                ldaa        $008D
                bita        #$80                ; test 008D.7
                bne         .LF720              ; branch ahead if it's set
                
                ldaa        fuelMapNumber       ; load fuel map number
                beq         .LF712              ; branch ahead if it's zero (limp home)
                
                cmpa        #$04                ; compare fuel map number with 4
                bcs         .LF6E9              ; return if less (fuel map is 1, 2 or 3)
                
                                                ; <-- code gets here only for maps 0, 4 and 5
.LF712          ldd         shortLambdaTrimR    ; load right bank short term trim
                subd        $C244               ; compare with XC422 (for R3526, value is $4721)
                bcs         .LF6E9              ; rtn if left bank value is < $4721
                
                ldd         shortLambdaTrimL    ; load left bank short term trim
                subd        $C244               ; compare with XC422 (for R3526, value is $4721)
                bcs         .LF6E9              ; rtn if right bank value is < $4721

.LF720          ldaa        $0072               ; $80 +/-
                ldab        $2048               ; also $80 +/-
                subb        #$80                ; subtract $80 for X2048
                aba                             ; add B to A (result to X0072)
                bcc         .LF731              ; branch ahead if result did not overflow
                
                ldab        $2048               ; $80 +/-
                bpl         .LF738              ; branch ahead if bit 7 is clear
                
                ldaa        #$FF                ; limit result to $FF

.LF731          ldab        $2048               ; $80 +/-
                bmi         .LF738              ; branch ahead if X2048 is >= $80
                
                ldaa        #$00                ; limit result to $00

.LF738          staa        $0072               ; write value to X0072

                ldaa        $2047
                oraa        #$40                ; set 2047.6
                staa        $2047

.LF742          ldd         mafLinear           ; load 16-bit linear MAF value
                std         $204F               ; save it to X204F (typically around 600 to 1400)
                ldaa        #$80
                staa        $2048               ; reset X2048 to 0x80
                clra
                ldab        $00AD               ; typically values 0, 5, 26 and 31
                std         $00C8
                ldaa        #$80
                ldab        $006E               ; value based on coolant temp (100 to 160)
                subd        $00C8
                std         $00C8
                clra
                ldab        $004F               ; battery backed value
                bmi         .LF76B              ; branch ahead if X004F is >= $80
                
                ldab        #$80                ; load $80
                subb        $004F               ; subtract X004F (result is positive)
                std         $00CA
                ldd         $00C8
                subd        $00CA
                bra         .LF76F

.LF76B          andb        #$7F                ; X004F is < $80, this op seems unnecessary
                addd        $00C8

;---------------------------------------
.LF76F          std         $00C8
                clra
                ldab        $0072               ; $80 +/-
                bpl         .LF77C              ; branch if X0072 < $80
                
                andb        #$7F                ; bit 7 is set and being cleared here
                addd        $00C8
                bra         .LF78B

.LF77C          ldab        #$80
                subb        $0072
                std         $00CA
                ldd         $00C8
                subd        $00CA
                bcc         .LF78B              ; branch ahead if borrow flag clear
                
                ldd         #$0000              ; else, limit value to zero

.LF78B          std         $2053               ; 16-bit stepper motor counter value
                cmpa        #$80
                bcc         .LF796
                
                ldaa        #$01
                bra         .LF7A2

.LF796          subd        #$80B4
                bcs         .LF79F
                
                ldaa        #$B4                ; $B4 is 180 decimal
                bra         .LF7A2

.LF79F          ldaa        $2054               ; load low byte of stepper motor counter

.LF7A2          staa        iacPosition         ; save it as stepper mtr position (zero to 180 value)
                rts
                
;------------------------------------------------------------------------------
;                  Fault Code 26 -- Very Lean Mixture Fault
;
;   This is called only by the inertia switch routine. This may the only
;   routine that alters the battery backed location X004F.
;
;   Note that the Very Lean Mixture and Air Leak faults are unused (masked out)
;   for Griff code and later.
;
;------------------------------------------------------------------------------
LF7A5           ldab        $0072               ; $80 +/-
                bmi         .LF7CC              ; branch ahead if X0072 >= $80
                
;----------------------------
; X0072 is less than $80
;----------------------------                
                ldd         $2049               ; road speed distance accumulator
                subd        $C24F               ; data value is $3E80 (16,000 dec)
                bcs         .LF7EF              ; return if distance accumulator is < 16000
                
                ldaa        faultBits_4B        ; no unmasked fault bits used in this byte!
                
                ldab        $0072               ; load X0072 again
                cmpb        $C251               ; data value is $71, compare with value in X0072
                bcc         .LF7CC              ; branch ahead if X0072 > $71
                
                cmpb        $C252               ; data value is $4E
                bcc         .LF7C5              ; branch ahead if X0072 > $4E
                
                oraa        #$02                ; <-- Set Fault Code 26 (very lean mixture fault -- unused)
                staa        faultBits_4B
                bra         .LF7EF              ; return

                                                ; code branches here if X0072 > $4E
.LF7C5          oraa        #$02                ; <-- Set Fault Code 26 (very lean mixture fault -- unused)
                staa        faultBits_4B
                ldab        $C251               ; data value is $71

;----------------------------
; X0072 is greater than $80
;----------------------------
.LF7CC          ldaa        $004F               ; battery backed location
                subb        #$80                ; subtract $80
                aba                             ; add B to A
                bcc         .LF7D9              ; branch if overflow
                
                ldab        $0072               ; load X0072
                bpl         .LF7DF              ; branch if < $80
                
                ldaa        #$FF

.LF7D9          ldab        $0072               ; load X0072 
                bmi         .LF7DF              ; branch if >= $80
                
                ldaa        #$00

.LF7DF          cmpa        #$8E                ; compare A with $8E
                bcc         .LF7EB              ; if A < $8E, branch to set X004F to $8E and rtn
                
                cmpa        #$49                ; compare A with $49
                bcc         .LF7ED              ; if A < $49, branch to store at X004F and return
                
                ldaa        #$49                ; else, set X004F to $49 and return
                bra         .LF7ED


.LF7EB          ldaa        #$8E                ; load A with $8E

.LF7ED          staa        $004F               ; store in battery-backed location X004F

.LF7EF          rts

;------------------------------------------------------------------------------
;                    Fault Code 26 -- Very Lean Mixture Fault
;
; This subroutine is called by the 'idleControl' routine. Engine speed must be
; above 1670 RPM for this to be called. It looks like this can clear Fault
; Code 26 which can be set in the ICI. This fault is masked out and is unused
; anyway so it may be possible to delete this code.
;
;------------------------------------------------------------------------------
LF7F0           ldaa        faultBits_4B        ; load fault bits
                bita        #$02                ; test unused fault code 26
                beq         .LF830              ; return if bit is clear
                
                ldd         targetIdleRPM       ; load engine idle target (16-bit value)
                subd        $C255               ; data value is $01F9 (subtract 505 RPM)
                subd        engineRPM           ; subtract actual eng RPM
                bcs         .LF829              ; branch ahead if (target - 505) < actual_RPM
                
                                                ; if here, RPM is lower than this
                ldaa        iacMotorStepCount   ; absolute value of stepper mtr adjustment
                bne         .LF830              ; return if iacMotorStepCount not zero (idle adjust progress)
                
                sei                             ; set interrupt mask
                ldaa        $008A               ; bits value
                anda        #$FE                ; clr X008A.0 (stepper mtr direction bit, 0 = open)
                staa        $008A
                ldaa        $C257               ; data value is $0F
                staa        iacMotorStepCount   ; set iacMotorStepCount to $0F (stepper mtr adj value)
                ldaa        $004F               ; load battery-backed value
                suba        #$49                ; subtract $49
                bcs         .LF81F              ; branch ahead if X004F < $49
                
                suba        $C257               ; subtract $0F
                bcc         .LF825              ; branch if result was > $0F
                
                adda        $0072               ; add X0072 to result
                staa        $0072               ; and store it

.LF81F          ldaa        #$49                ; load A with $49
                staa        $004F               ; store it as b-b value X004F
                bra         .LF829              ; branch

.LF825          adda        #$49                ; add $49 to A
                staa        $004F               ; store it as b-b value X004F

.LF829          ldaa        faultBits_4B        ; 
                anda        #$FD                ; clear unused fault code 26
                staa        faultBits_4B
                cli                             ; clear interrupt mask

.LF830          rts                             ; return

;------------------------------------------------------------------------------
;               *** Idle Air Control (stepper motor) Fault Test ***
;
;    This is called from the main loop. 
;    It handles the Idle Air Control Fault Bit -- Code 48
;------------------------------------------------------------------------------
LF831           ldaa        $0087
                bita        #$02                ; test 0087.1 (indicates air flow sensor fault)
                bne         .LF8B3              ; if 0087.1 is set, return (normally clr)
                
                ldaa        coolantTempCount    ; load coolant temperature
                cmpa        $C248               ; for R3526, value is $22 (a warmed engine)
                bcc         .LF8B3              ; if greater than (cooler than) this, return
                
                ldaa        $2047
                bita        #$01                ; test 2047.0 <-- (is this the idle mode bit??)
                beq         .LF8B3              ; if bit is clear, return
                
                ldd         ignPeriod          ; load spark period
                subd        #$3C67              ; subtract equivalent of 485 RPM
                bcc         .LF8B3              ; return if eng spd is LT 485 RPM
                
                ldaa        fuelMapLoadIdx      ; load the fuel map row index
                cmpa        $C266               ; for R3526, value is 0x28
                bcc         .LF8B3              ; if FM Row Index is > 0x28, return
IF BUILD_R3360_AND_LATER                
                ldaa        faultBits_49        ; fault bits (Griff does NOT have this)
                bita        #$06                ; test for O2 sensor faults
                bne         .LF8B3              ; if O2 sensor faults are active, return
ENDC                
                ldaa        $2048               ; initial value is $80
                bpl         .LF87C              ; branch ahead if X2048.7 is clr (less than $80)

                                                ; <-- $2048 is >= $80
                cmpa        $C24E               ; for R3526, value is $C6 (128 + 70 dec)
                bcs         .LF8B3              ; if LT 198, return
IF BUILD_R3360_AND_LATER                
                ldd         targetIdleRPM       ; idle target (Griff does NOT have this code)
                addd        $C7E1               ; add 200 dec
                subd        engineRPM           ; subtract eng RPM
                bcc         .LF8B3              ; return if eng spd is < (target + 200)
ENDC                
                ldd         $204F               ; typically varies around 600 to 1400 dec
                subd        mafLinear           ; subtract linear MAF (double op)
                bcs         .LF8AD              ; <-- branch to set Fault Code 48 (if MAF > $204F)
                
                subd        $C24B               ; subtract 150
                bcs         .LF8AD              ; ; <-- branch to set Fault Code 48 (if $204F is < 150 more than MAF)
                
                bra         .LF8B3              ; return

                                                ; <-- if $2048 is < 128
.LF87C          cmpa        $C24D               ; for R3526, value is $3A (58 dec)
                bcc         .LF8B3              ; rtn if value is > $3A
                
IF BUILD_R3360_AND_LATER                
                ldaa        $201D               ; this is the 16->0 startup down-counter
                bne         .LF8B3              ; branch ahead if down-counter not zero
                ldaa        shortLambdaTrimR    ; MSB of right side value (128 +/-)
                bmi         .LF88C              ; branch ahead if left trim value is > 32K
                coma                            ; negative range so perform 1's complement
                inca                            ; and increment

.LF88C          suba        #$80
                cmpa        $C7E3               ; for $3526, value is $40
                bcc         .LF8B3              ; return if...
                ldaa        shortLambdaTrimL    ; MSB of left side value (128 +/-)
                bmi         .LF899              ; branch ahead if right trim value is > 32K
                coma                            ; negative range so perform 1's complement
                inca                            ; and increment

.LF899          suba        #$80
                cmpa        $C7E3               ; for R3526, value is $40
                bcc         .LF8B3              ; rtn if carry clear
ENDC                

                ldd         mafLinear           ; load linear MAF (double value)
                subd        $204F               ; typically varies around 600 to 1400
                bcs         .LF8AD              ; branch ahead if...
                subd        $C249               ; for R3526, value is 150 dec
                bcc         .LF8B3              ; rtn if cc

.LF8AD          ldaa        faultBits_4C
                oraa        #$10                ; <-- Set Fault Code 48 (Idle Air Control Fault)
                staa        faultBits_4C

.LF8B3          rts

;------------------------------------------------------------------------------
;				Calculate_X2048	 (Idle Air Control related)
;
;   This is called from near the end of the main loop.
;
;------------------------------------------------------------------------------
LF8B4           ldab        #$80                ; inital value for $2048
                ldaa        ignPeriod          ; load high byte of spark period
                cmpa        #$92                ; cmpr with $92 (this is 200 RPM)
                bcc         .LF8C2              ; branch ahead if eng speed < 200 RPM
                ldaa        port1data           ; load P1
                bita        #$40                ; test bit 6 (test fuel pump relay)
                beq         .LF8C6              ; branch ahead if low (fuel pump ON)

                                                ; engine not running...
.LF8C2          stab        $2048               ;   reset 2048 to 128 and return
                rts
;-------------------------------------
                                                ; here if eng is running AND fuel pump is ON
.LF8C6          clra
                ldab        $00AD               ; load value from $00AD
                std         $00C8               ; store double at $00C8/C9 ($00C8 will be zero)
                ldaa        #$80
                ldab        $006E               ; this value based on coolant temp (see next routine)
                subd        $00C8               ; subtract $00C8/C9 from accumulators (double op)
                std         $00C8               ; store result at $00C8/C9 (double op)
                clra
                ldab        $004F               ; this value is from battery backed area
                bmi         .LF8E4              ; branch ahead if minus (less than $80)
                ldab        #$80                ; else, load $80 and subtract the value
                subb        $004F               ; 
                std         $00CA
                ldd         $00C8
                subd        $00CA
                bra         .LF8E8

.LF8E4          andb        #$7F
                addd        $00C8

.LF8E8          std         $00C8
                clra
                ldab        $0072
                bpl         .LF8F5
                andb        #$7F
                addd        $00C8
                bra         .LF904

.LF8F5          ldab        #$80
                subb        $0072
                std         $00CA
                ldd         $00C8
                subd        $00CA
                bcc         .LF904
                ldd         #$0000              ; limit 16-bit value to 0000

.LF904          std         $00C8
                bpl         .LF917
                anda        #$7F
                std         $00C8
                ldd         $2053               ; $2053 is a 16-bit counter value
                subd        $00C8
                bcc         .LF925

.LF913          ldab        #$00
                bra         .LF943

.LF917          ldd         #$8000
                subd        $00C8
                addd        $2053               ; $2053 is a 16-bit counter value
                bcc         .LF925

.LF921          ldab        #$FF
                bra         .LF943

.LF925          std         $00CA
                cmpa        #$80
                beq         .LF939
                bcc         .LF921
                cmpa        #$7F
                bcs         .LF913
                cmpb        #$80
                bls         .LF913
                subb        #$80
                bra         .LF943

.LF939          cmpb        #$80
                bcc         .LF921
                addb        #$80
                bcc         .LF943
                ldab        #$FF

.LF943          pshb                            ; push calculated value
                ldaa        $2059               ; this is a bits location
                anda        #$FE                ; clr 2059.0 (stepper mtr related??)
                staa        $2059               ;
                ldd         $00CA
                subd        $C262               ; for R3526 tune, value is $7FB9 (32697 dec)
                bcc         .LF964              ; branch ahead if 00CA/CB was >= this value
                ldd         engineRPM           ; load eng RPM (ranges from idle to 1950)
                subd        targetIdleRPM       ; subtract engine idle target speed
                bcc         .LF972              ; branch if eng speed is above target

.LF95A          ldaa        $2059               ; <- eng speed not above target
                oraa        #$01                ; set 2059.0 (stepper mtr related??)
                staa        $2059
                bra         .LF972
                                                ; 00CA/CB was >= 32697 dec
.LF964          ldd         $00CA
                subd        $C264               ; for R3526, value is $80B4 (32948)
                bcs         .LF972              ; branch ahead if $00CA/CB is < this value
                ldd         engineRPM           ; load eng RPM (ranges from idle to 1950)
                subd        targetIdleRPM       ; subtract engine idle target speed
                bcc         .LF95A              ; branch up if eng speed above target
                
                                                ; <-- eng RPM too high
.LF972          pulb                            ; pull calculated value
                ldaa        $2048               ; $2048 varies around 128 (100 to 140)
                sba                             ; subtract B from A
                bcs         .LF98A              ; branch ahead if B was > $2048
                suba        $C25A               ; for R3526, value is $02
                bcs         .LF99D
                ldab        $2048               ; initial (middle value) is 128
                subb        $C25A               ; for R3526, value is $02
                bcc         .LF99D
                ldab        #$00
                bra         .LF99D

.LF98A          tba                             ; xfer B to A
                suba        $2048               ;
                suba        $C25B               ;
                bcs         .LF99D
                ldab        $2048               ; 
                addb        $C25B               ; 
                bcc         .LF99D
                ldab        #$FF
                                                ; other than reset, $2048 is only written here
.LF99D          stab        $2048               ; $2048 typically varies between 100 and 140
                rts
                
;------------------------------------------------------------------------------
;           *** Calculate Coolant Temp based value at X006E ***
;
; This code is the same as that embedded subroutine 'idleControl' which is
; called by the main loop both when ADC table ends and every 80th time through.
;
; It was made into a separate routine here, to be called from the ICI.
;
; As the coolant temp count goes down (as temperature rises), X006E goes up
; from about 100 to 160 dec.
;
;------------------------------------------------------------------------------
LF9A1           ldx         #$C17B              ; coolant temperature table (9 values)
                ldaa        coolantTempCount    ; load coolant sensor count
                ldab        #$09                ; data table length is 9
                jsr         indexIntoTable      ; call the std temp based indexer
                suba        $00,x               ; subtract table value from coolant temp
                pshb                            ; push count value
                ldab        $12,x               ; load B from 3rd row of data table
                mul                             ; mpy remainder by 3rd row table value
                asld
                asld                            ; mpy results by 4
                pulb                            ; pull B (count) preserving just upper byte of mpy
                cmpb        #$08                ; compare index counter with 8
                bcs         .LF9BC              ; branch ahead if B is < 8
                adda        $09,x               ; add value from 2nd row of data table
                bra         .LF9BF              ; and branch ahead to store and return

                                                ; B < 8
.LF9BC          suba        $09,x               ; subtract value from 2nd row of data table
                nega                            ; negate it

.LF9BF          tab                             ; xfr A to B
                stab        $006E               ; store calculated value
                rts
code
