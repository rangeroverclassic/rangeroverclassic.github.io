;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       Ther are 3 main subroutines in this file, all having to do with
;   control of the stepper motor (Idle Air Control Valve).
;
;   LD609 - Returns engine coolant temp based idle delta.
;
;   LD613 - Large subroutine called by main loop.
;
;   driveIacMotor - Stepper motor routine
;
;   LDAD3 - Stepper motor drive subroutine called by driveIacMotor
;
;------------------------------------------------------------------------------

code

;------------------------------------------------------------------------------
; This routine is called from below to accumulate the engine idle target speed.
; It falls thru to the routine at LD609 but the results aren't used until D602
; is called immediately after D609.
;------------------------------------------------------------------------------
.LD602          addd        $00CE
                std         $00CE
                std         targetIdleRPM

;------------------------------------------------------------------------------
;           Return Engine Coolant Temperature based idle delta.
;
;   This is called from a couple of places in the Throttle Pot routine and
;   from 1 place below. It returns the idle speed delta based on coolant temp.
;   Range is about 300 cold to zero hot.
;
;   if ECT < $27 (hot)  --> return 0x0000 in AB
;   if ECT > $27 (cool) --> return 2 * (ECT - $27) in AB
;
;   ECT of $27 is about 83 C or 181 F
;------------------------------------------------------------------------------

LD609           ldab        coolantTempCount    ; load ECT sensor counts
                subb        #$27                ; compare with $27
                bcc         .LD610              ; branch ahead if ECT >= $27 (cooler than)
                clrb                            ; return 0-0 (when ECT is hotter than $27)
                
                                                ; <-- cooler than $27
.LD610          clra                            ; clear A
                asld                            ; return (2 * (ECT - $27))
                rts
;------------------------------------------------------------------------------
;
;                   This is an idle control subroutine
;
;	This routine is called from 2 places:
;		1) Main loop when mux list ends
;		2) New AMR code (every 80th time thru)
;
;	The interrupt mask is set before calling this and cleared after.
;
;------------------------------------------------------------------------------

;----------------------
; Calculate target idle
;----------------------
idleControl     ldd         baseIdleSetting
                std         $00CE               ; general purpose location
                ldaa        $008A               ; bits
                bita        #$08                ; test 008A.3 (A/C related, usually set in road tests)
                bne         .LD623              ; branch ahead if bit is set (meaning A/C is off)
                ldd         idleAdjForAC
                bsr         .LD602              ; branch to subroutine above to write value


.LD623          ldab        $008A
                bitb        #$20                ; test 008A.5 (0 = neutral or D90, 1 = drive for RR))
                bne         .LD62E              ; branch ahead if bit is set
                ldd         idleAdjForNeutral
                bsr         .LD602              ; branch to subroutine above to add value and write


.LD62E          ldab        $00DD               ; bits value
                bitb        #$04                ; test 00DD.2 (heated screen sense, 1=OFF, 0=ON)
                bne         .LD639              ; branch ahead if bit is set
                ldd         idleAdjForHeatedScreen
                bsr         .LD602              ; branch to subroutine above to add value and write


.LD639          bsr         LD609               ; rtns coolant temp based idle delta (range zero to ~300)
                bsr         .LD602              ; branch to sub (above) to add value and write

                ldab        $C158               ; only referenced here, value is $05
                stab        $00C9               ; see D717
;-----------------------------------------------------------	
; Compare target idle against actual engine RPM
;-----------------------------------------------------------	                                                ; *** start new code
                ldaa        $2059               ; bits value
                bita        #$10                ; test 2059.4 (stepper motor or idle related)
                beq         .LD657              ; branch ahead if bit is low
                ldd         $00CE               ; load current idle speed target
                subd        engineRPM
                bcs         .LD657              ; branch ahead if eng speed is GT idle target
                                                ; if here, idle is lower than target
                subd        $C7D8               ; value is 100 decimal (subtract additional 100 from result)
                bcs         .LD657              ; branch ahead if eng speed is LT target by less than 100
                clr         $00B3               ; clr idle speed delta if GT 100 RPM??
;-----------------------------------------------------------	
; This is the calculation of the coolant based value at
; X006E. This code is similar to the separate subroutine
; that was added later at XF9A1.
;-----------------------------------------------------------	
.LD657          ldx         #$C17B              ; coolant temperature table
                ldaa        coolantTempCount
                ldab        #$09                ; data table length is 9
                jsr         indexIntoTable      ; modifies index, A is preserved
                suba        $00,x               ; subtract indexed value from A (coolant temperature)
                pshb                            ; B is now $09 or less (but not less than zero)
                ldab        $12,x               ; load B from 3rd row of data table
                mul                             ; mpy remainder by 3rd row table value
                asld
                asld                            ; multiply by 4
                pulb                            ; pul B (index), A is math result
                cmpb        #$08                ; compare index with 08
                bcs         .LD672              ; branch ahead if B LT 08
                adda        $09,x               ; add value from 2nd row of data table
                bra         .LD675              ; and branch ahead to store and return


.LD672          suba        $09,x               ; subtract value from 2nd row of data table
                nega

.LD675          tab
                stab        $006E               ; store calculated coolant temp related value
;-----------------------------------------------------------	
; Check some things to see if idle control is needed.
;-----------------------------------------------------------	
                ldaa        $0085               ; bits value
                bita        #$04                ; test 0085.2 (set and tested in IS routine)
                bne         .LD690              ; rtn if 0085.2 is set
                bita        #$80                ; test 0085.7 (may indicate low eng RPM)
                beq         .LD691              ; branch ahead if 0085.7 is clr (engine running)
                ldab        ignPeriod
                cmpb        $C16F               ; for 3360 code, value is $53 (353 RPM)
                bcs         .LD691              ; branch ahead & continue if engine PW is LT $5300 (RPM > 353)
                ldab        coolantTempCount
                cmpb        $C17E               ; inside coolant temp table (value is $23)
                bcs         .LD691              ; branch ahead & continue if coolant temp is LT $23 (hotter than)

.LD690          rts
;------------------------------------------------------------------------------
; There are 3 branches to here from above.
; Code gets here if eng is running (RPM > 353) and coolant temp is hotter than
; 35 decimal.
;------------------------------------------------------------------------------
                                                ; only branches are from D680, D687 and D68E (just above)
.LD691          ldab        $0087
                bitb        #$04                ; test 0087.2 (stays set for both RTs)
                beq         .LD6BD              ; branch ahead if bit 2 is zero

                bita        #$02
                bne         .LD6BA              ; branch ahead to jmp if 0085.1 is set
                ldab        ignPeriod
                cmpb        $C16F               ; for 3360 code, value is $53 (353 RPM)
                bcc         .LD690              ; branch up (to rts) if engine PW is GT $5300 (RPM < 353)
                oraa        #$02                ; set 0085.1 (isn't this unnecessary? already set)
                staa        $0085
                ldab        neutralSwitchVal
                cmpb        #$4D                ; cmpr with $4D
                bcs         .LD6B9              ; rtn if neutral switch is LT $4D (in drive for RR)
                cmpb        #$B3                ; cmpr with $B3
                
IF BUILD_R3360_AND_LATER
                bcc         .LD6B9              ; rtn if neutral switch is GT $B3 (in park for RR)
ELSE
                bcc         .LD6B9A             ; rtn if neutral switch is GT $B3 (in park for RR)
ENDC                
                ldab        $2004
                orab        #$02                ; set 2004.1 when middle voltage at neutral switch (manual tranny?)
                stab        $2004

IF BUILD_R3360_AND_LATER
.LD6B9          rts
ELSE
.LD6B9		    ldaa	    $201F
		        anda	    #$DF                ; clear X201F.5
		        staa	    $201F
		        
.LD6B9A         rts		        
ENDC

;------------------------------------------------------------------------------
                                                ; the branch above (D699) is the only reference
.LD6BA          jmp         .LD73D              ; jump down to next section
;------------------------------------------------------------------------------
;    LD695 is the only way to get here (0087.2 must be zero)
;------------------------------------------------------------------------------
                                                ; code above branches here if 0087.2 is zero
.LD6BD          ldaa        $008A
                bita        #$02                ; test 008A.1 (set in fuel temp routine, always 1 per RR)
                bne         .LD6D9              ; branch ahead if 008A.1 is set
                bita        #$08                ; test 008A.3 (changes per RR)
                bne         .LD6CE              ; branch ahead if 008A.3 is set
                ldaa        coolantTempCount
                cmpa        $C17E               ; inside coolant temp table (value is $23)
                bcc         .LD6D9              ; branch ahead if coolant temp is GT (cooler than) $23

.LD6CE          ldx         $C0B0               ; for 3360, value is #0002
                ldd         $009F               ; related to fuel temp (stayed zero for RTs)

.LD6D3          dex
                beq         .LD6DA              ; this loops and does one asld (it's probably zero anyway)
                asld
                bra         .LD6D3

.LD6D9          clra

.LD6DA          ldab        $008A
                bitb        #$08                ; test 008A.3
                beq         .LD6ED
                ldab        coolantTempCount
                cmpb        $C17D               ; coolant temp table value
                bcs         .LD6ED
                cmpa        #$0C
                bcs         .LD6ED
                ldaa        #$0C

.LD6ED          adda        $C15D               ; value is $20
                staa        $00C8

                ldaa        $006E               ; calc value based on coolant temp (100 -> 160)
                ldab        $004F               ; load battery backed value
                bpl         .LD701              ; branch forward if 004F.7 is zero
                                                ; X004F is neg
                andb        #$7F                ; clr bit 7
                aba                             ; add B to A
                bcc         .LD70A
                ldaa        #$FF                ; limit value to $FF
                bra         .LD70A
                                                ; X004F is pos
.LD701          ldab        #$80
                subb        $004F
                sba                             ; subtract B from A
                bcc         .LD70A
                ldaa        #$00

.LD70A          tab                             ; xfer A to B
                subb        $00C8
                bcc         .LD711
                ldab        #$01

.LD711          ldaa        $008A
                bita        #$20                ; test 008A.5
                beq         .LD71D
                subb        $00C9               ; value is still 5 ? (see D642)
                bcc         .LD71D
                ldab        #$01
                                                ; B is new stepper mtr target
.LD71D          subb        iacPosition
                ldaa        $008A
                bcc         .LD728              ; if carry clr, B was GT IAC position, close SM
                                                ; *** Open stepper motor ***
                negb                            ; carry set, result is neg, open SM
                anda        #$FE                ; clr 008A.0 (stepper mtr direction bit, 0 = open)
                bra         .LD72A
                                                ; *** Close stepper motor ***
.LD728          oraa        #$01                ; set 008A.0 (stepper mtr direction bit, 1 = close)

.LD72A          staa        $008A
                stab        iacMotorStepCount
                ldaa        $0087
                oraa        #$04                ; set 0087.2 (stays set for both RTs, probably for 1-time code)
                staa        $0087
                ldaa        $2059
                oraa        #$08                ; set 2059.3
                staa        $2059

.LD73C          rts
;------------------------------------------------------------------------------
; Only path here is jump at D6BA (above) (if 0085.1 is set)
;------------------------------------------------------------------------------
                                                ; dest of a jmp above
.LD73D          ldaa        iacMotorStepCount
                bne         .LD73C              ; return if not zero
                ldab        $00AE               ; (1 of 5) zero for D90, high & low (or signed) numbers for RR
                ldaa        $00DD
                bita        #$04                ; test 00DD.2 (related to heated screen?)
                bne         .LD756
                bita        #$02                ; test 00DD.1 (related to heated screen?)
                bne         .LD761
                oraa        #$02                ; set  00DD.1
                staa        $00DD
                addb        $C1EB               ; value is $08, add to 00AE value
                bra         .LD761

.LD756          bita        #$02                ; test 00DD.1
                bne         .LD761
                oraa        #$02                ; set  00DD.1
                staa        $00DD
                subb        $C1EB               ; value is $08, subtract from 00AE value

.LD761          ldaa        $008A
                bita        #$08                ; test 008A.3 (possibly A/C related)
                bne         .LD774
                bita        #$04
                bne         .LD772
                oraa        #$04                ; set 008A.2
                staa        $008A
                subb        $C157               ; value is $1A (26d), subtract from 00AE value

.LD772          bra         .LD77F

.LD774          bita        #$04                ; test 008A.2
                bne         .LD77F
                oraa        #$04                ; set 008A.3
                staa        $008A
                addb        $C157               ; value is $1A (26d), add to 00AE value

.LD77F          bita        #$20                ; test 008A.5 (neutral switch?)
                bne         .LD78F
                bita        #$10                ; test 008A.4 (neutral switch?)
                bne         .LD78D
                oraa        #$10                ; set 008A.4
                staa        $008A
                addb        $00C9               ; value is still 5 ?

.LD78D          bra         .LD7A8

.LD78F          bita        #$10
                bne         .LD7A8
                oraa        #$10                ; set 008A.4
                staa        $008A
                subb        $00C9               ; value is still 5 ?
                psha
                ldaa        $C7DA               ; val is $18 (24d)
                staa        $00B3               ; idle speed adjustment
                ldaa        $2059
                anda        #$EF                ; clr 2059.4 (stepper mtr or idle related bit)
                staa        $2059
                pula

.LD7A8          stab        $00AE               ; (2 of 5)
                clrb
                bita        #$08
                bne         .LD7B2
                addb        $C157               ; value is $1A (26d)

.LD7B2          bita        #$20
                beq         .LD7B8
                addb        $00C9               ; value is still 5 ?

.LD7B8          ldaa        $00DD
                bita        #$04                ; test 00DD.2
                beq         .LD7C1
                addb        $C1EB               ; value is $08

.LD7C1          stab        $00AD               ; values 0, 5, 26 and 31 (only written here)
                ldab        $2047
                ldaa        ignPeriod
                cmpa        $C16F               ; value is $53 (353 RPM)
                bcc         .LD7D2              ; branch ahead if engine PW is GT $5300 (RPM < 353)
                orab        #$20
                stab        $2047               ; set  2047.5 (indicates eng RPM GT 350)

.LD7D2          ldaa        $0085               ; bits
                bitb        #$20                ; test 2047.5 (indicates eng RPM GT 350)
                beq         .LD805              ; branch down if eng RPM LT 350 (eng not running)
                bita        #$20                ; test 0085.5
                bne         .LD7F0

                oraa        #$20                ; set  0085.5
                staa        $0085
                ldaa        $0054               ; throttle pot min
                staa        $0052               ; throttle pot min (battery saved)
                ldaa        $0088
                oraa        #$04                ; set 0088.2
                staa        $0088
                ldaa        $C151               ; val is $32 (50 decimal)
                staa        $00B3               ; idle speed adjustment
                rts
;------------------------------------------------------------------------------
; Only path here is LD7DA (above), X0075 is zero to get here
;------------------------------------------------------------------------------
                                                ; only branched to from D7DA above (0085 is in A)
.LD7F0          ldab        $00B4               ; (1 of 3) load counter (often cycles 5 -> 0)
                beq         .LD7F9
                dec         $00B4               ; (2 of 3) decrement counter
                bra         .LD805

.LD7F9          ldab        $00B3               ; <- when counter is zero. B3 = idle speed adjustment
                beq         .LD805
                decb
                stab        $00B3               ; decrement idle speed adjustment
                ldab        $C14F               ; val is $05
                stab        $00B4               ; (3 of 3) reset counter to 5

                                                ; only from D7D6, D7F7 or fall thru
.LD805          psha
                ldaa        $008A
                ldab        $00AE               ; (3 of 5)
                beq         .LD81B
                bpl         .LD813
                negb
                anda        #$FE                ; clr 008A.0 (stepper mtr direction bit, 0 = open)
                bra         .LD815

.LD813          oraa        #$01                ; set 008A.0 (stepper mtr direction bit, 1 = close)

.LD815          staa        $008A
                stab        iacMotorStepCount
                pula
                rts
;------------------------------------------------------------------------------
; Only path here is LD80A (above) when X00AE is zero
;------------------------------------------------------------------------------

.LD81B          pula                            ; pull value from 0085 (bits)
                bita        #$20                ; test 0085.5
                beq         .LD827              ; rtn if zero
                ldab        $0086               ; bits value
                bmi         .LD828              ; branch to next section if 0086.7 is one
                clr         $00C0               ; else, clr X00C0 and rtn

.LD827          rts
;------------------------------------------------------------------------------
; Only path here is D822 (above). Conditionally increments 00B5/B6
;------------------------------------------------------------------------------

.LD828          clr         $00CC
                ldaa        $0087
                bita        #$40                ; test 0087.6 (eng RPM GT theshold)
                beq         .LD83F              ; branch ahead to continue if 0087.6 is clear
                ldaa        $008B
                anda        #$01                ; isolate 008B.0 (road speed GT 4)
                bne         .LD827              ; branch to return if road speed is GT 4
                ldx         $00B5               ; 00B5/B6 starts at -20 and varies to +59
                beq         .LD83F              ; branch to continue if 00B5/B6 is zero
                inx                             ; else increment it and return
                stx         $00B5
                rts
;------------------------------------------------------------------------------
; Two paths here:  D82F and D839 (above)
;------------------------------------------------------------------------------

.LD83F          tst         $00B3               ; idle speed adjustment (value is between zero and 40)
                bne         .LD827              ; if non-zero, branch up to return
                ldd         $00CE               ; still current idle speed target
                subd        engineRPM
                bcc         .LD88E              ; if RPM is LT target, branch down to other section
                ldaa        $0073               ; zero for D90, for RR: zero with 4s and 10s (stepper mtr rel.)
                beq         .LD866              ; if 0073 is zero, branch ahead
                ldaa        $C161               ; value is 0A
                suba        $C164               ; value is 06
                staa        $0073               ; this is where the 4 comes from
                jsr         LEE12               ; deals with 0073 and iacMotorStepCount
                clr         $0073               ; zero for D90, for RR: zero with 4s and 10s (stepper mtr rel.)
                ldaa        $C164               ; value is 06
                staa        $0071               ; occasionally init to 6 and decremented to zero        ;
                ldab        $C165               ; value is $14
                bra         .LD880

.LD866          ldaa        $0071               ; occasionally init to 6 and decremented to zero
                beq         .LD88E
                ldab        $0087
                bitb        #$40                ; test 0087.6 (eng RPM GT theshold)
                bne         .LD883
                deca
                staa        $0071               ; occasionally init to 6 and decremented to zero
                ldaa        $008A
                oraa        #$01                ; set 008A.0 (stepper mtr direction bit, 1 = close)
                staa        $008A
                ldaa        #$01
                staa        iacMotorStepCount
                ldab        $C166               ; value is 0x0C in 3360 code

.LD880          stab        $00B3               ; idle speed adjustment

.LD882          rts
;------------------------------------------------------------------------------
; Only path here is D86E above (eng RPM > threshold)
;------------------------------------------------------------------------------

.LD883          staa        $0073               ; zero for D90, for RR: zero with 4s and 10s (stepper mtr rel.)
                jsr         LEE12               ; deals with 0073 and iacMotorStepCount
                clr         $0071               ; occasionally init to 6 and decremented to zero
                jmp         .LD9D7
;------------------------------------------------------------------------------

.LD88E          ldaa        $008B
                anda        #$01                ; isolate 008B.0 (road speed GT 4)
                bne         .LD882              ; branch up to rts if road speed is GT 4 KPH

                ldaa        $0089               ; if here, road speed is low
                bmi         .LD882              ; rtn if 0089.7 is set
                ldd         ignPeriod
                subd        $C253               ; for 3360 code, value is $118B (1670 RPM)
                bcs         .LD882              ; branch up (to rts) if PW is LT $118B (RPM > 1670)

                jsr         LF7F0               ; the only call to this s/r (may clear unused fault code 26)
                ldaa        iacMotorStepCount
                bne         .LD882              ; rtn if iacMotorStepCount is not zero

                ldaa        $2047
                bita        #$01                ; test 2047.0 (is this the idle mode bit??)
                bne         .LD8FC              ; branch way down if bit is set
                oraa        #$01                ; else, set bit
                staa        $2047

;-----------------------------------------------------------
;		Calculate Value at 204F/50
;
; (same as code near CC8A)
; this code executes once every time 2047.0 is set and has
; to do with idle air control fault
;-----------------------------------------------------------
                ldaa        $2048               ; initial (middle) value is 128
                cmpa        #$80                ; 2048 may be for idle air control fault
                bcc         .LD8DD

;-------------------------------------        ; the code below is similar to something seen elsewhere
                ldaa        #$80                ; if 2048 is LT 128
                suba        $2048
                ldab        $C25C               ; value is 08
                mul
                std         $00C8
IF BUILD_R3360_AND_LATER                
                subd        #$05AB
                bcs         .LD8CE
                ldd         #$05AB
ELSE
                subd        #$0640
                bcs         .LD8CE
                ldd         #$0640
ENDC                
                std         $00C8

.LD8CE          ldd         mafLinear
                subd        $00C8
                bcc         .LD8D8
                ldd         #$0000

.LD8D8          std         $204F               ; <-- write 204F here (varies around 600 to 1400)
                bra         .LD8FC
;-------------------------------------
                                                ; if 2048 is GTE 128
.LD8DD          suba        #$80
                ldab        $C25C               ; value is 08
                mul
                std         $00C8
IF BUILD_R3360_AND_LATER                
                subd        #$05AB
                bcs         .LD8EF
                ldd         #$05AB
ELSE
                subd        #$0640
                bcs         .LD8EF
                ldd         #$0640
ENDC                
                std         $00C8

.LD8EF          ldd         mafLinear
                addd        $00C8
                bcc         .LD8F9
                ldd         #$FFFF

.LD8F9          std         $204F               ; <-- write 204F here (varies around 600 to 1400)
;-------------------------------------
; end idle air control fault code
;-------------------------------------

.LD8FC          ldaa        $2059
                bita        #$01                ; test 2059.0 (stepper mtr related??)
                beq         .LD904              ; (2059.0 may have stayed zero for RTs)
                rts
;------------------------------------------------------------------------------
; Only path here is D901 (just above)
;------------------------------------------------------------------------------

.LD904          ldaa        $0088
                oraa        #$01                ; set 0088.0 (set near eng start and stays set)
                staa        $0088
                clra
                staa        $0073               ; zero for D90, for RR: zero with 4s and 10s (stepper mtr rel.)
                staa        $0071               ; occasionally init to 6 and decremented to zero
                ldd         $00CE               ; still current idle speed target
                subd        engineRPM
                bcc         .LD91B              ; branch if eng RPM is lower than target
                inc         $00CC               ; cleared at D828, incremented to indicate RPM is GT target
                jsr         absoluteValAB

.LD91B          clr         $00CD               ; AB now contains abs value of delta
                                                ; <-- start loop
.LD91E          subd        $C173               ; for 3360, value is #000E, subtract from abs value of idle delta
                bcs         .LD928              ; branch if delta is LT 14
                inc         $00CD               ; X00CD is incremented for every 14 counts of idle delta
                bra         .LD91E              ; <-- end loop
                                                ; if here, idle delta is LT 14
.LD928          ldab        $00CD               ; load the (14 increment) counter into B
                subb        $C175               ; for 3360, value is #01
                bcc         .LD930
                clrb                            ; in this case, B is zero anyway
                                                ;
.LD930          cmpb        $C169               ; for 3360 code, value is $14
                bcs         .LD938
                ldab        $C169               ; for 3360 code, value is $14

.LD938          stab        $00CD               ; store the 14 increm counter (minus 1) - this is iacMotorStepCount
                stab        iacMotorStepCount
                beq         .LD94B

                clr         $00C0               ; if here, idle adjustment is needed
                ldaa        $2059
                anda        #$EF                ; clr 2059.4 (stepper mtr or idle related)
                staa        $2059
                bra         .LD999


.LD94B          ldab        $00C0
                cmpb        $C155               ; for 3360, value is 0xAF
                bcs         .LD996
                ldaa        $C156               ; for 3360, value is 0x28
                staa        $00B3               ; idle speed adjustment
                ldaa        $2059
                oraa        #$10                ; set 2059.4 (stepper mtr or idel related)
                staa        $2059
                ldaa        $0089
                anda        #$03                ; isolate 0089.1 and 0089.0
                bne         .LD97C              ; branch ahead if either bit is set
                jsr         LF658               ; the only call to this s/r
                ldab        $2047               ; bits
                ldaa        coolantTempCount
                cmpa        $C17D               ; val is $1C
                bcs         .LD977              ; branch ahead if CT is LT $1C (hotter than)
                cmpa        $C17E               ; inside coolant temp table (value is $23)
                bcs         .LD97C

.LD977          andb        #$BF                ; clr 2047.6 (normally 0)
                stab        $2047

.LD97C          ldab        $00DC
                bitb        #$08                ; test 00DC.3
                bne         .LD995
                orab        #$08                ; set  00DC.3
                stab        $00DC
                ldd         $0098               ; load down counter
                bne         .LD995              ; branch to rtn if not zero
                ldd         #$0020
                std         $0098               ; zero, so reset counter to 32 dec
                ldaa        $008D
                oraa        #$80                ; and set 008D.7 (bit went from 0 to 1 during both RTs)
                staa        $008D

.LD995          rts
;------------------------------------------------------------------------------
; Only path here is D950 (above)
;------------------------------------------------------------------------------

.LD996          inc         $00C0


.LD999          ldaa        $00CC
                beq         .LD9D1
                ldaa        $2047
                bita        #$04                ; test 2047.2 (VSS fail bit, normally 0)
                beq         .LD9CB
                ldaa        $006E               ; calc value based on coolant temp (100 -> 160)
                adda        $006F               ; nothing changes this (stayed zero for both RTs)
                cmpa        #$B4                ; $B4 = 180 dec
                bcc         .LD9B2
                adda        #$4B                ; $4B =  75 dec
                cmpa        #$B5
                bcs         .LD9B4

.LD9B2          ldaa        #$B4                ; $B4 = 180d

.LD9B4          suba        iacPosition
                beq         .LD9C7
                bcc         .LD9C2
                ldaa        #$01
                staa        $00CD
                staa        iacMotorStepCount
                bra         .LD9D1

.LD9C2          ldab        $00CD
                cba
                bcc         .LD9CB

.LD9C7          staa        $00CD
                staa        iacMotorStepCount

.LD9CB          ldaa        $008A
                oraa        #$01                ; set 008A.0 (stepper mtr direction bit, 1 = close)
                bra         .LD9D5

.LD9D1          ldaa        $008A
                anda        #$FE                ; clr 008A.0 (stepper mtr direction bit, 0 = open)

.LD9D5          staa        $008A

.LD9D7          ldab        $C150               ; value is $2D
                ldaa        iacMotorStepCount
                mul
                tsta
                bne         .LD9E5
                cmpb        $C153               ; value is $1C
                bcs         .LD9E8

.LD9E5          ldab        $C153               ; value is $1C

.LD9E8          stab        $00B3               ; idle speed adjustment
                rts

;------------------------------------------------------------------------------
; Stepper Motor Routine
;
; Active when: Road speed less than 3 mph; Throttle closed; Engine above 50 rpm
; Air valve open = 0 steps
; Air valve closed = 180 steps
;
; Called:
; 1) From end of main loop (if iacMotorStepCount is non-zero)
; 2) From Inertia Switch routine
; 3) From Coolant Temp routine (loops until iacMotorStepCount is zero)
;
; Note that X00C6/C7 is only used here
;------------------------------------------------------------------------------
driveIacMotor   tpa                             ; xfer CCR to A
                psha                            ; and push to stack
                ldaa        iacMotorStepCount
                beq         .LDA1D              ; if zero, branch to jmp to pop CCR and rtn
                ldaa        $2047
                bita        #$80                ; test 2047.7 (normally zero)
                beq         .LD9FC              ; branch if bit is low
                ldd         counterHigh         ; load counter value into A-B
                bra         .LD9FF


.LD9FC          jsr         LF0D5               ; update timers (returns 16-bit counter value in A-B)


.LD9FF          std         $00C8               ; store counter in 00C8/C9
                ldaa        $0085
                bita        #$04                ; test 0085.2 (indicates extra eng load??, No, IS run-0nce bit)
                beq         .LDA12              ; branch ahead if zero
                ldd         $00C8
                subd        $00C6               ; counter subtract value
                subd        #$0C35              ; subtract 3125 dec
                bcs         .LDA2D              ; if carry set, branch to jump to pop CCR and rtn
                bra         .LDA3D              ; carry clr, branch ahead


.LDA12          ldd         ignPeriod
                subd        $C253               ; for 3360 code, value is $118B (1670 RPM)
                bcs         .LDA1F              ; branch ahead if PW is LT $118B (RPM > 1670)
                ldaa        $008B               ; RPM LT 1670
                bita        #$40                ; test 008B.6 (1 = main voltage OK)

                                                ; code branches here if step count is zero
.LDA1D          beq         .LDA31              ; branch to jmp to pop CCR and rtn

.LDA1F          ldaa        $2038
                bita        #$40                ; test 2038.6
                bne         .LDA34
                ldd         $00C8
                subd        $00C6               ; counter subtract value
                subd        #$186A              ; subtract 6250 dec

.LDA2D          bcs         .LDA31              ; branch to jmp to pop CCR and rtn
                bra         .LDA3D

.LDA31          jmp         .LDAD0              ; pop CCR and return

.LDA34          ldd         $00C8
                subd        $00C6               ; counter subtract value
                subd        #$0C35              ; subtract 3125 dec
                bcs         .LDA31

.LDA3D          ldaa        $008A               ; code gets here from 2 places if carry clr
                eora        $2038               ; exclusive or the A reg with 2038
                bita        #$01                ; test eor of 008A.0 and 2038.0 (stppr mtr direction)
                bne         .LDAAF              ; branch ahead if only 1 of the 2 bits was set
                dec         iacMotorStepCount
                ldab        $0074               ; load SM drive value into B
                jsr         LDAD3               ; stepper motor sub-routine (below)
                ldaa        $008A
                bita        #$01                ; test 008A.0 (stepper mtr direction bit, 0 = open, 1 = close)
                beq         .LDA5F
                                                ; close
                tba                             ; xfer drive value from B into A
                asld                            ; shift left twice to create next drive value in A
                asld                            ;
                clr         $00CE               ; set X00CE to zero
                ldab        iacPosition
                incb                            ; increment stepper mtr position
                bra         .LDA6C

                                                ; open
.LDA5F          tba                             ; xfer drive value from B into A
                lsrd                            ; shift right twice to create next drive value in B
                lsrd
                tba                             ; xfer drive value to A
                ldab        #$FF
                stab        $00CE               ; set X00CE to $FF
                ldab        iacPosition
                beq         .LDA6C              ; skip decrement if zero
                decb                            ; decrement stepper mtr position

.LDA6C          staa        $0074               ; SM drive value
                anda        #$30                ; bits 5:4 are SM drive bits
                staa        $00CA               ; store at 00CA
                ldaa        port1data           ; P1.5 and P1.4 are SM drive signals
                anda        #$CF                ; mask 5:4 to zero
                oraa        $00CA               ; OR in new drive bits
                staa        port1data           ; <-- drive stepper mtr
                cmpb        #$B4                ; compare IAC position with limit of 180 dec
                bcs         .LDA80
                ldab        #$B4                ; if over, clip value to 180

.LDA80          cmpb        #$00                ; compare IAC position with zero
                bne         .LDA86
                ldab        #$01                ; if zero, limit it to 1

.LDA86          stab        iacPosition
                ldaa        $00AE               ; (4 of 5)
                beq         .LDA93              ;
                bmi         .LDA90              ;
;------------------------------------------------------------------------------
;   Note:   This area presented a problem during original disassembly and the
;           code can only be recreated by defining bytes.
;------------------------------------------------------------------------------
                
;-------------------------------------
;    When X00AE is Positive
;-------------------------------------
;        deca                ; decrement A
;        cmpa    #$4C        ; 4C op code is inca (cmpa result not used)
;-------------------------------------
;    When X00AE is Negative
;-------------------------------------
;        deca                ; need byte for alignment
;        FCB    $81                ; ditto
;.LDA90:                        ; value $81 is not used
;        inca                ; increment A
;-------------------------------------

                DB          $4A,$81

.LDA90          DB          $4C

                staa        $00AE               ; (5 of 5)

.LDA93          clr         $203A               ; stepper motor position?
                ldaa        $00CE
                beq         .LDAA4
                ldd         $2053
                subd        #$0001              ; decrement X2053/54
                bcc         .LDAAC
                bra         .LDAAF

.LDAA4          ldd         $2053
                addd        #$0001              ; increment X2053/54
                bcs         .LDAAF

.LDAAC          std         $2053

.LDAAF          ldd         $00C8
                std         $00C6               ; counter subtract value
                ldab        $203A               ; stepper motor position?
                incb                            ; increment 203A
                stab        $203A               ; stepper motor position?
                cmpb        #$04
                bne         .LDAD0              ; pop CCR and return
                ldab        $2038
                ldaa        $008A
                bita        #$01                ; test 008A.0 (stepper mtr direction bit, 0 = open, 1 = close)
                bne         .LDACB
                andb        #$FE                ; clear 2038.0
                bra         .LDACD

.LDACB          orab        #$01                ;   set 2038.0

.LDACD          stab        $2038

.LDAD0          pula                            ; pop the CCR
                tap                             ; and restore it
                rts
;------------------------------------------------------------------------------
; Branches here conditionally from DA4B only. B is loaded from 0074 (the
; stepper motor drive value). If B is one of the following 4 values, the
; routine just returns, otherwise, the stepper motor bits are examined and one
; of the 4 values is returned accordingly.
; 1E -> 1E (00011110)
; 78 -> 78 (01111000)
; E1 -> E1 (11100001)
; 87 -> 87 (10000111)
; Stepper Motor 00 -> 87
; Stepper Motor 10 -> 1E
; Stepper Motor 20 -> E1
; Stepper Motor 30 -> 78
;------------------------------------------------------------------------------

LDAD3           cmpb        #$1E
                beq         .LDAF3
                cmpb        #$78
                beq         .LDAF3
                cmpb        #$E1
                beq         .LDAF3
                cmpb        #$87
                beq         .LDAF3
                ldab        port1data           ; bits 5:4 are stepper motor state
                andb        #$30
                beq         .LDAF4
                cmpb        #$10
                beq         .LDAF7
                cmpb        #$20
                beq         .LDAFA
                ldab        #$78

.LDAF3          rts

.LDAF4          ldab        #$87
                rts

.LDAF7          ldab        #$1E
                rts

.LDAFA          ldab        #$E1
                rts
;------------------------------------------------------------------------------

code
