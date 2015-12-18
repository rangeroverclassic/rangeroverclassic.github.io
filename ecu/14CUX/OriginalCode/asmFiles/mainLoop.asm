;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       This contains the code withing the ICI re-entry point as well as the
;   main loop.
;
;
;   ICI Re-Entry Point
;       Normally an interrupt pushes the machine state to the stack area and
;   retrieves it, using the 'rti' instruction, before returning to normal
;   processing. The main interrupt in this software is the spark-triggered
;   Input Capture Interrupt (ICI) which does not terminate this way. Instead,
;   the software resets the stack pointer, and starts fresh at the iciReentry
;   address below. This was probably done for "robustness" since a corrupted
;   stack or stack pointer would really fuck things up.
;   
;   Main Loop
;       The main loop increments through the ADC control table, making one
;   measurement for every pass through the loop. The ADC control values in the
;   table tell the ADC which channel to measure and whether to measure with
;   8 or 10 bit resolution. The channel number also provides the software with
;   a means of looking up the appropriate service routine for that measurement.
;   The table of service routine address vectors is at 'adcVectors'. When bits
;   4, 5 and 6 are set in the ADC control value (usually value $FA) the code
;   takes a different path and the ADC table pointer pointer is reset for the
;   next pass.
;
;   
;   Note that there is a switch controlled call to a 'simulator' routine.
;   This should be left OFF.
;
;------------------------------------------------------------------------------

code

;------------------------------------------------------------------------------
;                        *** ICI Re-entry Point ***
;
; The reset code branches over 'reInitVars' to 'preMainLoop' (below) so this
; file must follow the reset file in the build sequence to keep the branch
; instruction within range.
;
; The ICI does not return normally (via RTI) but instead it resets the stack
; pointer jumps here (see notes above).
;
;------------------------------------------------------------------------------
iciReentry      jsr         keepAlive           ; this must be called periodically
                ldaa        $2047
                anda        #$7F                ; clr X2047.7 (controls timer is IACV routine)
                staa        $2047


preMainLoop     lds         #$00FF              ; init stack ptr to $00FF

;---------------------------------------
;   Service fault slowdown counter
; 
; Note that X00D0 and X00D1 were used
; as 2 separate 8-bit values in older
; code, but are used as a 16-bit value
; in later code.
;---------------------------------------

IF NEW_STYLE_FAULT_DELAY

                ldx         faultSlowDownCount  ; load 16-bit value into X
                cpx         $00D0               ; compare it with X00D0 (init to 65250)
                bne         .LCA60              ; branch ahead if not equal
                
                ldx         #$FEE2              ; load $FEE2 
                stx         faultSlowDownCount  ; reset 16-bit counter to 65250
.LCA60          stx         $00D0               ; store it here too

ELSE
			    ldaa	    $00D1		        ; older version
			    cmpa	    $00D0
			    bne	        .LCA5D
			    
			    ldaa	    #$E0
			    staa	    $00D1
.LCA5D          staa	    $00D0
			    
ENDC

;---------------------------------------
;              Service MIL
;
; If data value at XC7C2 is zero, turn
; MIL off and branch to next section. 
; For NAS, value is $FF.
;---------------------------------------
                ldaa        $C7C2               ; value will be $FF or $00 (MIL delay)
                bne         .LCA6F              ; branch if not zero 

                ldaa        port1data
                oraa        #$01                ; EFI warning light OFF
                staa        port1data
IF OBSOLETE_CODE
                bra         Write9x00           ; this is just a big waste of time
ELSE
                bra         checkForHiSpeed     ; branch to code for high-speed ADC table
ENDC


;----------------------------
; Start new style fault scan
;----------------------------
IF NEW_STYLE_FAULT_SCAN

.LCA6F          ldd         $2032               ; zeroed at startup, 16-bit EFI light (MIL) delay
                bne         .LCA7C              ; branch if not zero
                
                addd        #$0001              ; add 1 to delay counter
                std         $2032               ; store it
                bra         .checkFaultBits     ; branch to check for faults

.LCA7C          bita        #$80
                bne         .checkFaultBits
                ldab        $0085
                bitb        #$40                ; test 0085.6 (engine started flag)
                beq         Write9x00           ; branch to next section until engine starts

                oraa        #$80                ; set X2032.7 (a signal to code below)
                staa        $2032

                                                ; fault masks used here: $77,$BD,$00,$D0,$20,$00
                                                ; (see faultMasks in faults.asm)
.checkFaultBits ldaa        faultBits_49
                anda        #$77                ; check faultBits_49 exc. bits 7 and 3
                bne         .efiLampOn
                ldaa        faultBits_4A
                anda        #$BD                ; check faultBits_4A exc. bits 5 and 1
                bne         .efiLampOn
                ldaa        faultBits_4B
                anda        #$00                ; check faultBits_4B (no bits)
                bne         .efiLampOn
                ldaa        faultBits_4C
                anda        #$D0                ; check faultBits_4C bits 7, 6 & 4
                bne         .efiLampOn
                ldaa        faultBits_4D
                anda        #$20                ; check faultBits_4D bit 5 only
                bne         .efiLampOn
                ldaa        faultBits_4E
                anda        #$00                ; check faultBits_4E (no bits)
                beq         .efiLampOff         ;  (data corrupt & RAM fail checked previously)


.efiLampOn      ldaa        port1data           ; if here, fail bit was found
                anda        #$FE                ; EFI warning light ON
                staa        port1data
                ldaa        $2032
                oraa        #$80                ; set X2032.7 (a signal to code below))
                staa        $2032
IF OBSOLETE_CODE
                jmp         Write9x00
ELSE
                jmp         checkForHiSpeed
ENDC

.efiLampOff     ldaa        port1data           ; if here, no fault was found
                oraa        #$01                ; EFI warning light OFF
                staa        port1data
;----------------------------
; End new style fault scan
;----------------------------
ELSE
 
;---------------------------------------------------------------------------
; This is the way the fault checking is done in older code (including TVR).
; This method is not as good since unused bits can get through the mask
; and set the MIL.
;---------------------------------------------------------------------------
	                                            ; scan for set fault bits
.LCA6F		    ldaa	    $004D               
		        anda	    #$EF                ; mask out bit 4 (DTC 59 -- Group Fault)
		        oraa	    $004B               ; OR in all bits from X004B
		        oraa	    $004C               ; OR in all bits from X004C
		        anda	    #$F0                ; low nibble unused for all three
		        oraa	    $0049               ; OR in all bits from X0049
		        oraa	    $004A               ; OR in all bits from X004A
		        beq	        Write9x00           ; if zero, no faults, branch ahead
		        
		        ldaa	    port1data
		        anda	    #$FE                ; EFI warning light ON
		        staa	    port1data
ENDC                
;------------------------------------------------------------------------------


;------------------------------------------------------------------------------
; This code is within the ICI Re-entry Point.
;
; The shiftEngDebugData routine shifts the loaded double value left by the
; number of bits in B. In the R3652 tune, B is zero, so the values 65, 5B and
; 5C are loaded unaltered into 9000, 9100 and 9200 respectively.
;
; Information (likely from internal memos) indicates that these locations
; ($9000, $9100, $9200) were used with a special development unit that
; had additional hardware (D-A converters) at these locations.
;
; Other that consuming clock cycles, this code has no effect whatsoever on
; a normal production 14CUX unit, and should be removed from the build once
; there is no longer any need to perform a binary comparison against a
; factory image.
;
;   Execution clock cycles are in brackets.
;   Subroutine shiftEngDebugData is 22 clk cycles min.
;   Total = 61 + ( 3 * 22) = 127 clocks
;
; Added Note:
;   Since this code is executed once for every ICI, it can be used to offset
;   some of the simulation code which adds up to 64 clock cycles per main loop
;   iteration.
;
;------------------------------------------------------------------------------

IF OBSOLETE_CODE
Write9x00       sei                                 ; [2]
                ldx         engDataA                ; [5]
                ldab        engInitDataA            ; [4]
                jsr         shiftEngDebugData       ; [6]
                staa        $9000                   ; [4]
                ldx         engDataB                ; [5]
                ldab        engInitDataB            ; [4]
                jsr         shiftEngDebugData       ; [6] 
                staa        $9100                   ; [4]
                ldx         engDataC                ; [5]
                ldab        engInitDataC            ; [4]
                jsr         shiftEngDebugData       ; [6]
                staa        $9200                   ; [4]
                cli                                 ; [2]
ELSE
Write9x00       nop         ; [2] (used for label only)
ENDC

;------------------------------------------------------------------------------
;                      *** ADC Control Table Selection ***
;
; This code is within the ICI Re-entry Point.
;
; This block of code selects either the standard ADC control table from the
; current fuel map or a special ADC table (at XC231) under high RPM and high
; throttle conditions. The special ADC table is heavily loaded with road speed
; measurements. High RPM and TPS implies high road speed. The increased VSS
; frequency requires more frequent sampling.
;
; The first ADC conversion is triggered here outside of the main loop because
; the conversion takes a certain amount of time. Inside the loop, the ADC
; value is read first and then the next reading is triggered to be read the
; next time thru the loop.
;
;------------------------------------------------------------------------------
checkForHiSpeed ldaa        ignPeriod           ; load MSB of ignition period
                cmpa        #ignPeriodHiSpeed   ; compare MSB of period with $07 ($0700 = 4185 RPM)
                bcc         normalSpeed         ; branch ahead if RPM < 4185
                
                ldd         throttlePot             ; if here RPM > 4185, load 10-bit Throttle Pot
                subd        wideThrottleThreshold   ; subtract $02CD (70% throttle)
                bcs         normalSpeed             ; branch ahead if TPS < 70%

                                                ; if here, RPM > 4185 and TPS > 70%
                ldx         #hiRpmAdcMux        ; load address of special ADC table ($C231)
                ldaa        $201F
                oraa        #$10                ; set X201F.4 (to indicate this high-speed condition)
                staa        $201F
                ldaa        #$FF
                staa        $2076               ; init counter to $FF (used to slow down switch over)
                bra         startAdcReads

normalSpeed     ldaa        $2076               ; branches here if no need for hi-speed ADC mux table
                beq         useNormalAdcMux     ; if counter is zero, it's time to switch back to normal
                deca                            ; else, just decrement the delay counter
                staa        $2076               ; and store it
                ldx         #hiRpmAdcMux        ; load address of high-speed table
                bra         startAdcReads

useNormalAdcMux ldaa        $201F               ; if here, we are using the normal ADC table
                anda        #$EF                ; clear X201F.4 (to indicate normal)
                staa        $201F
                ldx         adcMuxTableStart    ; load address of normal fuel map specific table

startAdcReads   stx         adcMuxTablePtr      ; store pointer in the working (incrementing) location
                ldaa        $00,x               ; get the 1st value from the table
                staa        AdcControlReg1      ; trigger 1st ADC measurement


;------------------------------------------------------------------------------
;
;                              *** Main Loop ***
;
; This is the starting point for the main loop. The loop increments thru the
; ADC control table, calling the corresponding service routine from the vector
; table (see adcVectors.asm). When bits 4, 5 and 6 are set in the control byte
; (usually value $FA) the code takes a different path and the control table
; pointer is reset.
;
; The end-of-table code path includes A/C service, PROM checksum test, EFI
; warning light code (NAS only?), call to a large subroutine, stay-alive
; toggle and fuel pump shut-off (if timed out).
;
;------------------------------------------------------------------------------

LCB2A           ldx         adcMuxTablePtr      ; load ADC table working (incrementing) pointer
                ldab        $00,x               ; get next value from table
                bitb        #$70                ; check for bits 6:4 set (indicates end of list)
IF BUILD_R3365
                bne         .LCB35              ; branch ahead if bits are not zeros (end of list)
                jmp         .LCBC4A             ; not end of list, so jump ahead
ELSE                
IF BUILD_R3360_AND_LATER                
                bne         .LCB35              ; branch ahead if bits are not zeros (end of list)
                jmp         .LCBC4              ; not end of list, so jump ahead
ELSE
                beq		    .LCBC4              ; older code, branch ahead if not end-of-list
ENDC
ENDC

;------------------------------------------------------------------------------
; This section executes only when ADC control list terminates (upper nibble= F)
;------------------------------------------------------------------------------
.LCB35          ldaa        $0085
                anda        #$EF                ; clear X0085.4 (low indicates end of list)
                staa        $0085
                pshb                            ; push B to stack (ADC control value)                
;-----------------------------------------------------------
; A/C service (executes when RPM < 1627)

; X00E2.7 is set when RPM > 1627 and cleared when < 1627
;-----------------------------------------------------------
                tst         $00E2               ; test X00E2.7
                bmi         .LCB5A              ; branch to skip A/C if set (RPM > 1627)
                
                                                ; if here, RPM < 1627
                ldaa        $00B8               ; down-counter set to 44 dec in A/C routine
                beq         .LCB4A              ; branch to continue A/C routine if zero
                
                deca                            ; otherwise, decrement the down-counter
                staa        $00B8               ; store it
                bra         .LCB5A              ; and branch to next section
                                                
.LCB4A          ldaa        port2data           ; counter reached zero
                ldab        $008A
                bitb        #$08                ; test X008A.3 (A/C  1= OFF, 0 = ON)
                bne         .LCB56
                oraa        #$04                ; X008A.3 is zero, set P2.2 (A/C compressor)
                bra         .LCB58

.LCB56          anda        #$FB                ; X008A.3 is one,  clr P2.2 (A/C compressor)

.LCB58          staa        port2data

;-----------------------------------------------------------
;                   PROM Checksum Test
;
; This will take almost half a second to run to completion.
; If ignition sparks start before this is finished, this
; test is interrupted and never completed. This is due to
; bit X0086.3 being set in the ICI.
;-----------------------------------------------------------
.LCB5A          ldaa        $0086               ; X0086.3 indicates memory test complete
                bita        #$08                ; test X0086.3
                
          
IF BUILD_R3383
                bne         .LCBAF              ; branch to next section, if complete
ELSE          
                
IF BUILD_R3360_AND_LATER                
                bne         .romTestDone        ; branch to next section, if complete
ELSE
                bne         .LCBAF              ; branch to next section, if complete
ENDC
ENDC           

                clrb                            ; start test by clearing sum location B
                ldx         #romStart           ; romStart = $C000

.calcROMChksum  addb        $00,x               ; * Loop Start *    add add indexed value to B
                jsr         keepAlive           ;                   toggle the stay-alive timer
                inx                             ;                   increment the index register
                bne         .calcROMChksum      ; * Loop End *      repeat until address $FFFF
                
                stab        romChecksum         ; store the checksum
                cmpb        #$01                ; compare it with $01
                beq         .romChksumGood      ; branch if equal
                
                ldaa        faultBits_49 
                oraa        #$01                ; set fault code 29 (ROM checksum fail)
                staa        faultBits_49
                staa        romChecksumMirror

.romChksumGood  ldaa        $0086
                oraa        #$08                ; set X0086.3 high (memory test complete)
                staa        $0086
                
;-----------------------------------------------------------
;               EFI (MIL) Warning Light 
;
; This section is not in Griffith Code (possibly NAS only)
;
;-----------------------------------------------------------                

IF NEW_STYLE_MIL_CODE
                                                ; this code may be startup flash of warning light
.romTestDone    ldaa        $C7C2               ; load XC7C2 again (will be $00 or $FF)
                beq         .LCBAF              ; branch if zero (usually TVR and non-NAS)
                
                ldd         $2032               ; delay counter for EFI warning light
                bita        #$80                ; test X2032.7 (possibly set above)
                bne         .LCBAF              ; branch ahead if it's set
                
                addd        #$0001              ; otherwise, add 1
                std         $2032
                subd        #$02CA              ; this value may act as a time delay
                bcs         .LCBA9              ; branch while X2032 is less than this
                
                ldaa        $2032
                oraa        #$80                ; set X2032.7
                staa        $2032
                ldaa        port1data
                oraa        #$01                ; EFI warning light OFF
                staa        port1data
                bra         .LCBAF

.LCBA9          ldaa        port1data
                anda        #$FE                ; EFI warning light ON
                staa        port1data
ENDC

.LCBAF          sei                             ; set interrupt mask
                jsr         idleControl         ; call IACV related subroutine
                jsr         keepAlive           ; toggle the stay-alive
                cli                             ; clr interrrupt mask
                dec         fuelPumpTimer       ; decrement the fuel pump shut-off counter
                bne         .LCBC0              ; turn off fuel pump when counter reaches zero

                                                ; the A register was disturbed by the idleControl             
                oraa        #$40                ;  subroutine, so this looks like a code bug
                staa        port1data           ; Port 1.6 high (fuelPumpTimer is zero, fuel pump OFF)

.LCBC0          ldx         adcMuxTableStart    ; end-of-list, so reset ADC table pointer back to start
                dex                             ; decremented here due to pre-incrementing below
                pulb                            ; pull the current ADC control value back from stack

;------------------------------------------------------------------------------
; This code executes for every ADC table entry including the last one.
; (upon entering, B accum is value from ADC control table)
;------------------------------------------------------------------------------

IF BUILD_R3365                                  ; code above branches here if ADC mux bits 6:4 are clear
.LCBC4A         pshb                            ; push ADC control byte to stack
.LCBC4          tst         $0085               ; test X0085.7 (indicates low or no engine RPM)
                bpl         .LCBCE              ; branch ahead if 0085.7 is clr (engine running)
                
                jsr         LF04D               ; cold start injector chattering (below 0 deg F)
ELSE

.LCBC4          tst         $0085               ; test X0085.7 (indicates low or no engine RPM)
                bpl         .LCBCE              ; branch ahead if 0085.7 is clr (engine running)
                
                pshb                            ; push ADC control byte to stack
                jsr         LF04D               ; cold start injector chattering (below 0 deg F)
                pulb                            ; pull ADC control byte from stack
ENDC                

.LCBCE          ldaa        AdcStsDataHigh      ; read the ADC status/dataHigh register
                bita        #$40                ; test ADC busy flag
                bne         .LCBC4              ; branch back if busy
                
                anda        #$03                ; save upper 2 bits of 10 bit data
                staa        $00C8               ; store it in temporary location
                staa        $00B9               ; store it here too but this location unused
                ldaa        AdcDataLow          ; read low 8 bits
                staa        $00C9               ; 10-bit ADC value is now at X00C8/C9
                staa        $00BA               ;                        and X00B9/BA
                

IF BUILD_R3365                
		   	    ldaa	    $007A
		   	    cmpa	    #$0A
		   	    bcc	        .LCBF8
		   	    cmpa	    #$07
		   	    bcs	        .LCBF8
		   	    ldaa	    #$27
		   	    staa	    AdcControlReg1
		   	    ldaa	    #$C8
		   	    staa	    AdcDataLow
		   	    jsr	        LFA46
.LCBF8	    	pulb

ENDC

                ldaa        $01,x               ; get next ADC control value
                anda        #$8F                ; force bits 6,5,4 low (ADC doesn't need them)
                staa        AdcControlReg1      ; write ADC control reg (triggers convert)
                inx                             ; increment ADC control table ptr
                stx         adcMuxTablePtr      ; store it for next time
                ldx         #adcVectors         ; list of 16 ADC service routine vectors
                andb        #$0F                ; limit B to range of 0 through 15
;------------------------------------------------------------------------------
; Important Note: Simulation Mode is for bench testing only.
;
;   When calling the simulator, A = don't care, B = channel number (0 thru F),
;   X = #adcVectors, X00C8/C9 = 8 or 10-bit ADC reading
;   (need to preserve B and X)
;------------------------------------------------------------------------------
IF SIMULATION_MODE
                jsr         simulation          ; software simulation routine
ENDC
                aslb                            ; double value in B to convert to 16-bit pointer
                abx                             ; add B (offset) to X (adcVectors)
                jsr         keepAlive           ; toggle stay-alive timer
                ldaa        $00C9               ; reload low byte of ADC reading
                cli                             ; clear interrupt mask
                ldx         $00,x               ; load service routine address pointer from table
                
                jsr         $00,x               ; <-- call ADC service routine

                ldaa        $2059               ; load X2059 bits value
                bita        #$20                ; test X2059.5 (set below or when ICI starts)
                bne         .LCC1A              ; branch ahead if bit is 1
                
                bita        #$40                ; test X2059.6 (also set when ICI starts)
                beq         .LCC1A              ; branch ahead if bit is 0
                
                ldd         altCounterHigh      ; reading alternate avoids clearing TOF
                subd        $205D               ; subtract counter value written in ICI
                subd        #$4E20              ; subtract 20000 decimal
                bcs         .LCC1A              ; branch if altCounterHigh is less
                
                ldaa        $2059
                oraa        #$20                ; set 2059.5
                staa        $2059

.LCC1A          jsr         sciService          ; call serial port service routine
                jsr         LF0D5               ; update timers (also returns 16-bit counter in A-B)
                
;-----------------------------------------------------------
; This code section re-inititializes the  MPU registers
; every 20th time through the code. X2037 is used as the
; counter for this.
;-----------------------------------------------------------
                ldaa        $2037               ; counter varies between zero and 20
                cmpa        #$14                ; compare with 20 decimal
                beq         .LCC2A              ; branch ahead if equal to 20
                
                inca                            ; if not, increment it
                bra         .LCC53              ; and branch ahead to store it

                                                ; start MPU re-init code
.LCC2A          ldd         $2035               ; X2035 is never initialized and is otherwise unused
                subd        #$1262              ; so this is old obsolete code
                beq         .LCC52              ; never (or almost never) branches

                ldd         #$FFFE              ; re-init data direction regs
                std         port1ddr
                staa        port4ddr
                ldaa        timerCSR            ; enable Input Capture Interrupt (ICI)
                oraa        #$12                ; set P20 (coil input) to positive edge trigger
                staa        timerCSR
                ldd         #$050A
                std         sciModeControl      ; set serial port to 7812.5 baud
                ldaa        #$C0
                staa        ramControl          ; enable internal RAM , set Standby bit
                ldaa        timerCntrlReg1
                oraa        #$A0                ; OCF3 and ICF2
                staa        timerCntrlReg1
                ldaa        #$53                ; enable Input Cap Int 1 and Out Cmpr Int 2
                staa        timerCntrlReg2      ; low 2 bits are read-only

.LCC52          clra                            ; the 'never used' branch label
.LCC53          staa        $2037               ; store the zero through 20 counter

;---------------------------------------------------------------------
; This code was added about the time that the ECU part number changed
; from PRC to AMR. Similar to the code block above, this also uses a
; counter (X207E) and executes every 80th time through. The value 80
; comes from the data section at address XC259.
;---------------------------------------------------------------------
                inc         $207E               ; counter increments 0 through 80
                ldaa        $C259               ; data value is 80
                cmpa        $207E               ; compare counter with 80
                bcc         .LCC76              ; branch down near end of loop if counter < 80
                
                clr         $207E               ; counter is 80, so reset it to zero

                ldaa        $2047               ; this code executes every 80th time through
                bita        #$10                ; test X2047.4 (a coolant temp related bit)
                beq         .LCC76              ; if zero, branch to skip section
                
                ldaa        $0087
                bita        #$04                ; test X0087.2
                bne         .LCC78              ; if set, branch ahead to skip idleControl and continue
                
                sei
                jsr         idleControl         ; IACV related subroutine
                cli

.LCC76          bra         .LCCF2              ; branch down to stepper motor call and end of loop

;-----------------------------------------------------------
; This code section is executed 79 out of 80 times through
;-----------------------------------------------------------
.LCC78          jsr         LF5F0               ; this routine can reset X204B/4C to 50, rtns $00 or $FF in A accum
                beq         .LCCEF              ; branch ahead if $00 was returned
                
                ldaa        $2047               ; bits value
                bita        #$04                ; test X2047.2 (VSS failure bit)
                bne         .LCCEF              ; branch down if road speed sensor failure
                
                jsr         LF831               ; IACV (stepper motor) fault test subroutine
                jsr         LF611               ; 1670 RPM counter subroutine
                
;-----------------------------------------------------------
;             Calculate Value at X204F/50
;
; This code block is similar to one found in idelControl.asm
; (nead .LD8CE) It's executed only when eng RPM > 1670.
; This looks like a fault detection routine for Idle Air
; Control Valve (IACV).
;-----------------------------------------------------------
                
                ldaa        $2047
                bita        #$08                ; test X2047.3 (1 means RPM > 1670 for a short time)
                beq         .LCCEF              ; branch down if bit is zero

;-----------------------------------------------------------
; This code is executed only when eng RPM > 1670
;-----------------------------------------------------------
                sei                             ; set interrupt mask
                bita        #$01                ; test X2047.0
                bne         .LCCE5              ; branch ahead if bit is set
                
                oraa        #$01                ; set X2047.0
                staa        $2047               ; store X2047
                
                ldaa        $2048               ; initial (middle) value is 128
                cmpa        #$80                ; is value > 128
                bcc         .LCCC6
;----------------------------
; X2048 is less than 128
;----------------------------
                ldaa        #$80                ; load 128
                suba        $2048               ; subtract value to get delta below 128
                ldab        $C25C               ; this value is in the range of 6 to 8
                mul                             ; multiply delta by this value
                std         $00C8               ; store 16-bit result in temporary location
IF BUILD_R3360_AND_LATER                
                subd        #$05AB              ; subtract 1451 decimal
                bcs         .LCCB7              ; branch down if value was less
                ldd         #$05AB              ; otherwise, limit the value to 1451 decimal
ELSE
                subd        #$0640              ; subtract 1600 decimal
                bcs         .LCCB7              ; branch down if value was less
                ldd         #$0640              ; otherwise, limit the value to 1600
ENDC                
                std         $00C8               ; store value

.LCCB7          ldd         mafLinear           ; load linearized MAF
                subd        $00C8               ; subtract the calculated value
                bcc         .LCCC1              ; branch if no underflow
                ldd         #$0000              ; else limit value to $0000

.LCCC1          std         $204F               ; store 204F/50
                bra         .LCCE5
                
;----------------------------
; X2048 is greater than 128
;----------------------------
.LCCC6          suba        #$80                ; subtract 128 to get delta above 128
                ldab        $C25C               ; this value is in the range of 6 to 8
                mul                             ; multiply delta by this value
                std         $00C8               ; store 16-bit result in temporary location
                
IF BUILD_R3360_AND_LATER                
                subd        #$05AB              ; subtract 1451 decimal
                bcs         .LCCD8              ; branch down if value was less                
                ldd         #$05AB              ; otherwise, limit the value to 1451 decimal
ELSE                                            ; Older Version:
                subd        #$0640              ; subtract 1600
                bcs         .LCCD8              ; branch down if value was less
                ldd         #$0640              ; otherwise, limit the value to 1600
ENDC                            
                std         $00C8               ; store value

.LCCD8          ldd         mafLinear           ; load linearized MAF
                addd        $00C8               ; add the calculated value
                bcc         .LCCE2              ; branch if no overflow
                ldd         #$FFFF              ; else limit value to $FFFF

.LCCE2          std         $204F               ; store X204F/50

;----------------------------
.LCCE5          ldaa        $2059
                bita        #$01                ; test X2059.0 (signal to close stepper mtr?)
                bne         .LCCEF
                jsr         LF63A               ; may set stepper mtr to close by 30 steps
;----------------------------
; End of 1670 RPM code
;----------------------------
.LCCEF          jsr         LF8B4               ; calculate X2048

.LCCF2          cli                             ; clear interrupt mask
                ldaa        iacMotorStepCount   ; load stepper motor adjust value
                beq         .LCCFA              ; skip subroutine if value is zero
                jsr         driveIacMotor       ; stepper motor drive subroutine

.LCCFA          jmp         LCB2A               ; jump back to top of loop

;------------------------------------------------------------------------------

code
