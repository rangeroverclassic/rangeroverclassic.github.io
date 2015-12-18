;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013  Initial file.
;              26-Mar-2014  Corrected a few comments.
;
;   Description:    Input Capture Interrupt
;
;   This is the spark interrupt which is often referred to in this code as
;   the ICI (Input Capture Interrupt). It is called every time a spark plug
;   fires and it contains the heart of the 14CUX fuel control.
;
;   It is entered like a normal interrupt. In other words, the state of the
;   microprocessor is automatically saved to the stack (program counter,
;   index register, A accumulator, B accumulator, and condition code register).
;   Normally an interrupt returns via the 'rti' (return from interrupt)
;   instruction, which restores all the registers. However, this interrupt,
;   when terminating, resets the stack pointer (erasing all memory of it's
;   past) and jumps to a re-entry point.
;
;   There are 4 possible states for this interrupt and there are two bits
;   that are toggled in the ICI to keep track of the state.
;
;                                   X0088.7   X008C.0
;       1) Right bank fueling         0          0
;       2) Right bank non-fueling     0          1
;       3) Left bank fueling          1          0
;       4) Left bank non-fueling      1          1
;
;   This results in firing one injector bank for each engine revolution.
;
;
;   Eng.                            
;    RPM   ICI Rate   ICI Period
;  ---------------------------------
;    200    13.3 Hz     75.00 ms
;    600    40.0 Hz     25.00 ms
;   1000    66.6 Hz     15.00 ms
;   2000   133.3 Hz      7.50 ms
;   3400   266.7 Hz      4.4  ms
;   4185   279.0 Hz      3.6  ms
;   5000   333.3 Hz      3.00 ms
;   5502   366.8 Hz      2.73 ms
;   6188   412.5 Hz	     2.42 ms  <--Griff limit
;
;   
;   Profiling Code
;       Code has been added to the entry and exit points for this interrupt
;   that toggles a PAL output. This output can be viwed with an oscilloscope
;   time analysis. This option is controlled in 'config.asm' and is normally
;   turned off. Although this additional code changes the timing, there is
;   a block of obsolete code (at LDCD2) that can be used to compensate.
;
;------------------------------------------------------------------------------
code

IF USE_4004_BIT4_FOR_ICI
inputCapInt     ldaa        i2cPort             ; [4] profiling code
                oraa        #$10                ; [2] 4004.4 high
                staa        i2cPort             ; [4]

			    ldab        $2059               ; X2059.5 controls 1-time startup code
ELSE			    

inputCapInt     ldab        $2059               ; X2059.5 controls 1-time startup code

ENDC                                                
                bitb        #$20                ; test X2059.5
                bne         .LDB73
                                                ; *** Start: 1-time startup code ***
                ldaa        $205C               ; this is the only area X205C is used
                inca                            ; X205C usually just counts from 0 to 1
                cmpa        #$08                ; compare with 8
                bcc         .LDB6E              ; branch ahead if X205C > 8
                staa        $205C               ; 
                bitb        #$40                ; test X2059.6 (here to LDB63 executes once)
                bne         .LDB63              ; branch to LDB63 (reset) if bit is set
                ldd         altCounterHigh      ; reading alternate avoids clearing TOF
                std         $205D               ; X205D/5E is only written here and written once
                ldaa        $2059
                oraa        #$40                ; set X2059.6
                staa        $2059
                bra         .LDB73
                                                ; this jumps back to reset
.LDB63          lds         #$00FF              ; reset stack pointer
                ldaa        timerCSR            ; resets timer?
                ldd         icrHigh             ; input capture reg (clears or resets)
                cli                             ; clear interrupt mask
                jmp         iciReentry          ; go to re-entry point

.LDB6E          orab        #$20                ; set X2059.5
                stab        $2059               ; *** End: 1-time startup code ***



;-----------------------------------------------------------
; Code branches here after startup
; Turn off PROM Checksum Test
; (plus sets unused bit 008B.1, can delete)
;-----------------------------------------------------------

IF BUILD_R3365
;-----------------------------------------------------------
; Defender Only (R3365)
;-----------------------------------------------------------

.LDB73	   	    ldaa	    $007A               ; load ignition period MSB
	   	        cmpa	    #$08                ; about 3662 RPM
	   	        bcc	        .LDB73A             ; branch ahead if LT 3662 RPM
	   	        
	   	        ldaa	    #$27                ; 
	   	        staa	    AdcControlReg1
	   	        ldaa	    #$C8
	   	        staa	    AdcDataLow
	   	        jsr	        LFA46

.LDB73A         ldab        $0086               ; set X0086.3	   	        
ELSE

.LDB73          ldab        $0086               ; set X0086.3	   	        
ENDC
                orab        #$08                ; (X0086.3 indicates memory test complete)
                stab        $0086               ; 
                ldab        $008B               ;
                bitb        #$02                ; test X008B.1 (unused)
                bne         .reassertMap5
                
                orab        #$02                ; set  X008B.1 (unused)
                stab        $008B

;-----------------------------------------------------------
; If fuel map is locked, re-assert Map 5
;-----------------------------------------------------------
.reassertMap5   ldab        fuelMapLock
IF BUILD_R3360_AND_LATER
                beq         .LDB95
ELSE
                beq         .LDAB7
ENDC                
                ldab        #$05
                stab        fuelMapNumber
                stab        fuelMapNumberBackup
                ldd         #fuelMap5
                std         fuelMapPtr

;-----------------------------------------------------------
; This section is not found in later code. In older code,
; X201F.5 can be cleared in idleControl.
;-----------------------------------------------------------
IF BUILD_R3360_AND_LATER
    ; nothing
ELSE    

.LDAB7		    ldab	    $2034       ; a counter
		        cmpb    	#$03        ; compare with 3
		        bcc	        .LDB95      ; branch when counter reaches 3
		        
		        cmpb	    #$02        ; compare with 2
		        bne	        .LDAD1      ; branch to increment when counter is 0 or 1
		        
		        ldaa	    $2000       ; counter is 2, load neutral switch value
		        cmpa	    #$B3        ; compare with $B3
		        bcs	        .LDAD1      ; branch to increment if value < $B3 (not in drive)
		        
		        ldaa	    $201F
		        oraa	    #$20        ; set X201F.5
		        staa	    $201F
.LDAD1		    incb                    ; increment the counter
		        stab	    $2034       ; and store it
ENDC

;-----------------------------------------------------------
;       Select TPS or MAF for measurement in ICI
;
; Below 4883 RPM, TPS is always measured
; Above 4883 RPM, MAF and TPS alternate
;-----------------------------------------------------------
.LDB95          ldab        $201F               ; bits value
                ldaa        ignPeriod           ; load ignition period MSB
IF BUILD_R3365                
                cmpa        #$07                ; compare with $07
ELSE
                cmpa        #$06                ; compare with $06
ENDC                
                bcc         .LDBAA              ; branch to set TP if eng spd < 4883 RPM
                
                ldaa        $008C
                bita        #$01                ; test X008C.0 (this bit is toggled)
                bne         .LDBAA              ; branch ahead to TP if 008C.0 is set

                ldaa        #$02                ; ADC Value for 10-bit air flow (MAF)
                orab        #$40                ; set X201F.6 (MAF being measured)
                bra         .LDBAE

.LDBAA          ldaa        #$03                ; ADC Value for 10-bit throttle pot (TPS)
                andb        #$BF                ; clr X201F.6 (TPS being measured)


.LDBAE          staa        AdcControlReg1      ; store ADC channel and trigger measurement
                stab        $201F               ; store X201F, bit 6 = 1 (MAF) or 0 (TPS)
                
;------------------------------------------------------------------------------
;                   Measure and save engine ignition period
;
; The MPU's Input Capture Register latches the 1 MHz free running counter on
; the Input Capture transition. Since the counter often wraps (or overflows)
; which results in Timer Overflow Flag (TOF) being set, there is an additional
; variable (X00B2) which is used to keep track of this.
;
; Software uses this value to measure the spark to spark time. The value is
; right shifted 1 bit before storage and use, which reduces the resolution to
; 2 uSec units. This is probably done to facilitate the math since this avoids
; perceived negative numbers. The timer value is saved in X00C4/C5 to be used
; in the next interrupt.
;
;------------------------------------------------------------------------------
                ldaa        timerCSR            ; reading timerCSR and then icrHigh resets ICF1
                lds         #$00FF              ; why is stack being reset again?
                ldd         icrHigh             ; read 16-bit input capture register & reset ICF1
                std         $00C8               ; store counter snapshot at 00C8/C9
                std         $00CA               ; also store at 00CA/CB (later use by code below at DC52)
                ldab        timerCSR
                andb        #$20                ; isolate timerCSR bit 5 (Timer Overflow Flag)
                beq         .LDBDD              ; branch ahead if TOF is clear
                                                ;
                inc         $2001               ; <-- overflow happened, increment road speed counter
                bne         .LDBCD              ; branch ahead if it hasn't wrapped
                dec         $2001               ; otherwise, clip it at $FF

                                                ; does this check for another, more recent overflow??
.LDBCD          ldd         counterHigh         ; load current counter value (also resets the TOF)
                subd        $00C8               ; subtract ICR snapshot value
                bcc         .LDBD7              ; branch overflow did not recently happen
                
                ldab        #$01                ; overflow happened, load $01 to store at X00B2
                bra         .LDBDD              ; branch ahead to load X00B2 into A

                                                ; <-- overflow did not recently happen
.LDBD7          clrb                            ; clear B to conditionally write to X00B2
                ldaa        $00B2               ; load X00B2
                inca                            ; increment the value
                bne         .LDBDF              ; if non-zero, branch ahead to zero X00B2

                                                ; code branches here if TOF is clear
.LDBDD          ldaa        $00B2               ; load X00B2

.LDBDF          stab        $00B2               ; store B in X00B2 for later use (usually zero or one)

                ldab        $00C8               ; a = 00B2, b = high byte of 16-bit capture reg
                lsrd                            ; logical shift right (div by 2)
                ror         $00C9               ; rotate 00C9 right (carry shifts in from 'lsrd' op)
                stab        $00C8               ; store the upper 16 bits back in X00C8
                cmpa        #$01                ; compare A with $01
                bcs         .LDBFA              ; branch ahead if A was zero (X00C8/C9 is the result)

                bne         .LDBF5              ; branch if not zero
                ldd         $00C8               ; load X00C8/C9
                subd        $00C4               ; subtract X00C4/C5 (last timer value divided by 2)
                bcs         .LDBFE              ; if carry set, branch to store ignition period

.LDBF5          ldd         #$FFFF              ; else, clip it at $FFFF
                bra         .LDBFE

.LDBFA          ldd         $00C8               ; when here, X00C8/C9 is the count divided by 2
                subd        $00C4               ; X00C4/C5 is last ICR snapshot value divided by 2 (0 to 32K)

.LDBFE          std         ignPeriod           ; store ignition period

;------------------------------------------------------------------------------
; Check bit that is set (below) when engine starts
;------------------------------------------------------------------------------
                ldaa        $0085               ; bits value
                bita        #$40                ; test X0085.6 (engine started flag)
                bne         .LDC52              ; branch down if engine already running
;------------------------------------------------------------------------------
; Engine NOT Running (Code from here to LDC52 stops executing once eng starts)
;------------------------------------------------------------------------------
                ldaa        ignPeriodFiltered       ; load filtered ignition period
                cmpa        #(ignPeriodEngStart-1)  ; $39 (514 RPM) or $4D (380 RPM for cold weather chip)
                bcc         .LDC4A                  ; branch if RPM is less than this
                
                ldaa        $00A7                   ; X00A7 is a counter used for a small code execution delay
                cmpa        #startupDelayCount      ; usually $02 but $04 for cold weather chip
                bcs         .LDC4F                  ; branch ahead if 00A7 is LT 04 (small code execution delay)
                
;-----------------------------------------
                ldaa        $0085               ; this section executes once only after X00A7 reaches compare count
                oraa        #$40                ; set 0085.6 (set bit to control 1-time code)
                staa        $0085
                jsr         initRAMFromExt      ; this subroutine checks for differences between the battery-backed RAM
                                                ; and it's mirror in external memory, if diffs, code re-syncs memory
IF BUILD_R3360_AND_LATER                
                ; nothing          
ELSE                
		        ldaa	    #$FA                ; for older code, reset 1 Hz startup down-counter to 250 seconds
		        staa	    $2039               ; (newer code sets this elsewhere and to a much lower number)
ENDC                
                
                ldaa        fuelMapLock         ; load the fuel map lock value from the data section
                bne         .checkMAFFault      ; branch ahead if locked
                
                ldaa        $008C               ; if here, fuel map is unlocked
                bita        #$40                ; test X008C.6 (indicates data corrupted or ram fail)
                beq         .checkMAFFault      ; branch ahead if no failure
                
                ldaa        fuelMapNumber       ; battery-backed RAM failure so load fuel map number
                staa        fuelMapNumberBackup ; and store it in the battery-backed RAM location (X0050)

.checkMAFFault  ldd         mafDirectHi         ; load the MAF high value
                subd        #$0066              ; subtract $0066 (500 mV)
                bcc         .LDC38              ; branch ahead if > 500 mV
                
                ldaa        $0087
                oraa        #$02                ; set X0087.1 (indicates MAF fault)
                staa        $0087

.LDC38          ldab        coolantTempCount    ; load ECT sensor count
                cmpb        $200F               ; from 3rd last value in FM data struct (about 78 to 85 C))

IF BUILD_R3360_AND_LATER                
                bcc         .LDC48              ; branch ahead if cooler (later code)
ELSE
                bcc         .LDB8D              ; branch ahead if cooler (TVR)
ENDC                
                ldab        $C1FF               ; data value is $03
                stab        $2020               ; init right  bank startup timer
                stab        $2021               ; init left bank startup timer

IF BUILD_R3360_AND_LATER
                ; nothing for later code
ELSE

.LDB8D		    ldab	    $201F               ; bits value
		        bitb	    #$20                ; test X201F.5
		        beq	        .LDC52              ; branch ahead if zero
		        
		        ldab	    $004C
		        orab	    #$80                ; set neutral switch fault code 69
		        stab	    $004C
ENDC

.LDC48          bra         .LDC52              ; branch to next section
;-----------------------------------------
                                                ; code jumps here if eng speed is LT 514 (380 for cold chip)
.LDC4A          clr         $00A7               ; X00A7 is the code delay counter mentioned above
                bra         .LDC52              ; branch to next section
;-----------------------------------------

.LDC4F          inc         $00A7               ; increment the counter

;-----------------------------------------
; Engine running condition code
;-----------------------------------------
.LDC52          ldd         $00CA               ; still the 16-bit ICR snapshot value (see LDBBD area)
                lsrd                            ; divide by 2
                std         $00C4               ; store timer (0-32K range) in X00C4/C5 for use on next call (above)

                ldaa        $0088
                bita        #$01                ; test X0088.0
                bne         .checkForHiRPM      ; branch if bit is set

;-----------------------------------------
; Stepper motor adjustment
;-----------------------------------------
                ldab        $0087
                bitb        #$40                ; test X0087.6  bit is set when eng RPM > (1200 + ECT delta)
                beq         .checkForHiRPM      ; branch if idle is OK
                
                ldab        iacMotorStepCount   ; this is absolute value of pending IACV adjustment
                bne         .checkForHiRPM      ; branch ahead to skip this section if value not zero
                                                ; (meaning that an adjustment is already pending)
                
                oraa        #$01                ; set X0088.0
                staa        $0088
                ldd         throttlePot         ; load 10-bit TPS value
                subd        #$0070              ; this is the default value (547 mV))
                bcs         .checkForHiRPM      ; branch ahead if TPS value is less than 547 mV
                
                ldab        $C15D               ; data value is $20 or $1D
                stab        iacMotorStepCount   ; set stepper motor to close by 32 (or 29) counts
                ldaa        $008A
                oraa        #$01                ; set X008A.0 (stepper mtr direction bit, 1 = close)
                staa        $008A

.checkForHiRPM  ldaa        ignPeriod           ; load MSB of ignition period
                cmpa        #$07                ; $0700 = 4185 RPM
                bcs         .LDCB0              ; branch ahead if RPM > 4185

;---------------------------------------------------
; This subracts 1 from a purge valve timer variable
; (if not zero) every 4th time through.
;
; This section skipped if RPM > 4185
;---------------------------------------------------
                ldaa        $008C
                bita        #$01                ; test X008C.0 (toggled bit)
                bne         .LDC97              ; branch ahead if bit is 1

                tst         $0088               ; test X0088.7 (toggled bit)
                bmi         .LDC97              ; branch ahead if 0088.7 is 1
                
                ldd         $0098               ; a purge valve timer variable
                beq         .LDC97              ; branch ahead if zero
                
                subd        #$0001              ; otherwise, subtract 1
                std         $0098               ; and store it

;---------------------------------------------------
; Condition bit X00DC.0 (related to short term trim)
;
; This section skipped if RPM > 4185
;---------------------------------------------------
.LDC97          ldaa        $008B
                anda        #$01                ; isolate X008B.0 (road speed > 4 KPH)
                beq         .LDCAA              ; branch ahead if road speed is < 4 KPH
                
                ldd         throttlePot         ; load TPS value
                subd        #$019A              ; subtract 410 (about 40% or 2.0 volts)
                bcc         .LDCAA              ; branch ahead if TPS > 40%
                
                ldaa        $00DC
                oraa        #$01                ; set X00DC.0 (VSS > 4 and TPS < 40%)
                bra         .LDCAE

.LDCAA          ldaa        $00DC
                anda        #$FE                ; clr X00DC.0 (VSS < 4 or TPS > 40%)

.LDCAE          staa        $00DC

;---------------------------------------------------
; A/C compressor control
;---------------------------------------------------
.LDCB0          ldab        $00E2               ; bits
                ldaa        ignPeriodFiltered   ; load filtered ignition period (MSB only)
                suba        #$12                ; subtract $12
                bcc         .LDCBC              ; branch ahead if RPM < 1628)
                
                orab        #$80                ; set X00E2.7 (when RPM > 1628)
                bra         .LDCBE

.LDCBC          andb        #$7F                ; clr X00E2.7 (when RPM < 1628)

.LDCBE          stab        $00E2
                tstb                            ; test X00E2.7 which was just set/clrd
                bpl         .LDCD2              ; if 0, branch ahead to next section (RPM < 1628)
                
                ldaa        port2data           ; if here, RPM > 1628
                tst         $008C               ; test X008C.7 (A/C control bit)
                bmi         .LDCCE              ; if high, branch ahead to set P22 high
                
                anda        #$FB                ; P22 low (A/C compressor)
                bra         .LDCD0

.LDCCE          oraa        #$04                ; P22 high (A/C compressor)

.LDCD0          staa        port2data           ; write to port

;-------------------------------------------------------------------------------
;                            Obsolete Code
;                            
;   The X4004 register is decoded in the PAL to discrete outputs. Bits 5 and 6
;   are used for the I2C to the OBDD and come out of the PAL at pins 35 and 36.
;
;   Bit 7, which is used here, comes out at pin 37 but it looks dead ended on
;   the board due to missing components.
;
;   The number in brackets is clock execution clock cycles
;   Path 1 = 11 + 13 = 24
;   Path 2 = 11 + 10 = 21
;   This code block takes 21 or 24 clock cycles to execute.
;
;   Using the USE_4004_BIT4_FOR_ICI bit adds 20 clock cycles to the ICI.
;   Simulation adds 9 clocks (off) or 20 clocks (on) for the TPS/MAF.
;   HO2S simulation adds 36 plus 6 (jsr) for a total of 42.
;-------------------------------------------------------------------------------

.LDCD2          ldd         throttlePot         ; [4] load 10-bit TPS value
                subd        #$00B9              ; [4] subtract $B9 (about 18% throttle)
                bcs         .LDCE3              ; [3] branch if < 18% to drive X4004.7 low

                ldaa        i2cPort             ; [4] TPS > 18%
                oraa        #$80                ; [2] drive X4004.7 high
                staa        i2cPort             ; [4]
                bra         .LDCEB              ; [3] and branch to next section


.LDCE3          ldaa        i2cPort             ; [4] TPS < 18%
                anda        #$7F                ; [2] drive X4004.7 low
                staa        i2cPort             ; [4]

;------------------------------------------------------------------------------
;						Read ADC Result (TPS or MAF)
;
;   Below 4883 RPM the TPS is always read.
;   Above 4883 RPM the TPS and MAF alternate.
;   The jmp at the end of this section skips the calculation of TPS Direction
;   & Rate and the 24-bit TPS related value.
;------------------------------------------------------------------------------
.LDCEB          clr         $00CE               ; to be used much later in linearizeMAF
                ldaa        $0086
                oraa        #$02                ; set X0086.1 (MAF initialized bit?)
                staa        $0086
                ldaa        $008C
                bita        #$01                ; test X008C.0 (0 = MAF, 1 = TPS)
                bne         .LDD10              ; if 1, branch to read TPS at LDD10
                
                ldaa        $201F
                bita        #$40                ; test X201F.6 (air flow/throttle pot)
                beq         .LDD0D              ; if 0, conflicting bits, branch to jump to O2 test
                                                ; TODO: this needs to be understood better
                
;----------------------------------------------------------
;                   MAF Simulation
; Simulation adds 9 clocks when OFF and 20 clocks when ON            
;----------------------------------------------------------
IF SIMULATION_MODE
                ldaa        $2072               ; [4] load simulation control byte
                cmpa        #SIM_CONTROL_BYTE   ; [2] compare it with SIM_CONTROL_BYTE
                bne         .skip_sim           ; [3] branch if simulation is off

                ldaa        $2062               ; [4] MAF Simulation Bytes
                ldab        $2063               ; [4]
                bra         .sim                ; [3]
ENDC

.skip_sim       ldaa        AdcStsDataHigh      ; read 10-bit MAF (triggered earlier)
                ldab        AdcDataLow          ; 

.sim            anda        #$03                ; mask 10-bit value
                std         mafDirectLo         ; store it as both high and low
                std         mafDirectHi

IF BUILD_R3365                
.LDD0D          jmp         .LDE70A             ; jump ahead to O2 test
ELSE
.LDD0D          jmp         .LDE79              ; jump way down to O2 test
ENDC

;----------------------------------------------------------
;                   TPS Simulation
;----------------------------------------------------------
IF SIMULATION_MODE
.LDD10          ldaa        $2072               ; [4] load simulation control byte
                cmpa        #SIM_CONTROL_BYTE   ; [2] compare it with SIM_CONTROL_BYTE
                bne         .skip_sim2          ; [3] branch if simulation is off
                
                ldaa        $2064               ; [4] TPS Simulation Bytes
                ldab        $2065               ; [4]
                bra         .sim2               ; [3]
                
.skip_sim2      ldaa        AdcStsDataHigh      ; read 10-bit TPS (triggered earlier)
ELSE
.LDD10          ldaa        AdcStsDataHigh      ; read 10-bit TPS (triggered earlier)
ENDC                                
                ldab        AdcDataLow
                
.sim2           anda        #$03                ; mask 10-bit value                
                jsr         TpFaultCheck        ; TP fault check routine, rtns TPS val, tests X0085.7
                bpl         .LDD22              ; branch if X0085.7 is 0 (0 = engine running)
                
                std         $0061               ; (eng cranking) 24-bit value (store TP * 256)
IF BUILD_R3365                
                jmp         .LDE70A             ; (eng cranking) jump ahead to O2 test
ELSE
                jmp         .LDE79              ; (eng cranking) jump ahead to O2 test
ENDC
                
;------------------------------------------------------------------------------
;       Set or Clear X0087.0 which control Open/Closed Loop
;
; Normal path is from the bpl, just above to here. TPS being read and engine
; running. X0087.0 is set or cleared here. This bit is used for open/closed
; loop control. (bit is set when TPS > 40% and ECT cooler than 122 F)
;------------------------------------------------------------------------------
.LDD22          subd        #$019A              ; subtract 410 dec from TPS (40% or 2.0 volts)
                bcs         .LDD33              ; branch ahead to clr bit if TPS < 2.0 volts

                ldaa        coolantTempCount    ; load ECT sensor count
                cmpa        #$51                ; compare with $51
                bcs         .LDD33              ; branch ahead if ECT hotter than 50 C (122 F)
                
                ldaa        $0087
                oraa        #$01                ; set X0087.0 (to force open loop)
                bra         .LDD37

.LDD33          ldaa        $0087               ; if here, conditions are OK for closed loop
                anda        #$FE                ; clr X0087.0 (to allow closed loop)

.LDD37          staa        $0087               ; store it

;-------------------------------------------------------------------------------
;       Set or Clear X00E2.3 based on TPS (30%) and ECT (50 C)
;				
; But it looks like it's never used so we can delete this.
;-------------------------------------------------------------------------------
                ldd         throttlePot         ; load 10-bit TPS value
                subd        #$0133              ; subtract 307 dec from TPS (30% or 1.5 Volts) 
                ldaa        $00E2               ; ldaa does not affect carry
                bcc         .LDD4C              ; branch ahead to clr X00E2.3 if TPS > 1.5 Volts
                
                ldab        coolantTempCount    ; load ECT sensor count
                cmpb        #$51                ; compare with $51
                bcc         .LDD4C              ; branch ahead to clr X00E2.3 if colder than 50 C (122 F)
                
                oraa        #$08                ; set X00E2.3 (TPS < 1.5V and ECT hotter than 50 C)
                bra         .LDD4E

.LDD4C          anda        #$F7                ; clr X00E2.3 (TPS > 1.5V or ECT colder than 50 C)

.LDD4E          staa        $00E2               ; store it

;-------------------------------------------------------------------------------
;                       Throttle Pot Calculation
;
; When RPM < 4185, continue to next section (TPS Direction & Rate), else
; call a TPS related routine, set the 24-bit value = (TP * 256) and jump down
;-------------------------------------------------------------------------------
                ldaa        ignPeriod           ; load ignition period (MSB only)
IF BUILD_R3365                
                cmpa        #$08                ; compare with $08
ELSE
                cmpa        #$07                ; compare with $07
ENDC                
                bcc         .LDD60              ; branch ahead if < 4185 RPM

                jsr         LF423               ; 
                ldd         throttlePot         ; load TPS value
                std         $0061               ; store TPS value as 24-bit value

.LDD5D          jmp         .LDE70              ; jump to end of next section (RPM GT 4185)

;-------------------------------------------------------------------------------
;				Calculate Throttle Direction and Rate
;
; Code only gets here from the bcc above (when RPM < 4185).
; Note that the data tables at C0F8 and C731 are identical for R3526 tune.
; In original code, TPS D&R is stored in X005D/5E
;
; The data table used here is the 6 row x 10 column table.
;-------------------------------------------------------------------------------
.LDD60          ldx         #$C0F8              ; point to start of data table
                ldab        fuelMapNumber       ; load fuel map number
                beq         .LDD6E              ; branch ahead to use $C0F8 if fuel map 0
                
                ldab        #$82                ; else, need to add offset to base map ptr
                ldx         fuelMapPtr          ; load index with fuel map pointer
                abx                             ; add $82 to find the table

.LDD6E          ldaa        coolantTempCount    ; load ECT sensor count
                ldab        #$0A                ; number of columns in table
                jsr         indexIntoTable      ; this indexes to the correct temperature bracket

                ldd         throttlePot         ; load the TPS value
                subd        $00D9               ; subtract last TPS value (saved last time through)
                bcs         .LDD83              ; branch ahead if X00D9 > TPS (throttle closing)
                
                cmpb        #$02                ; TPS reading was greater so subtract 2 from positive remainder
                bcc         .LDD8F              ; branch ahead if TPS > (X00D9 plus 2) (throttle opening)
;---------------------
; Throttle is steady
;---------------------
.LDD7F          ldd         $00D9               ; load last saved value
                bra         .LDD99              ; branch to common code with last saved value
;---------------------
; Throttle is closing
;---------------------
.LDD83          cmpb        #$FD                ; TPS < X00D9, compare negative value with -3
                bcc         .LDD7F              ; if cc, value was more positive so branch up to steady throttle
                
                ldaa        $008B               ; if here, throttle is really closing
                oraa        #$20                ; set X008B.5 (this is the throttle_closing bit)
                staa        $008B
                bra         .LDD95
;---------------------
; Throttle is opening
;---------------------
.LDD8F          ldaa        $00D3
                oraa        #$40                ; set X00D3.6 (this is the throttle_opening bit)
                staa        $00D3
                                                ; throttle opening or closing gets to here (not steady condition)
.LDD95          ldd         throttlePot         ; save current TPS value...
                std         $00D9               ;  for next time through

;------------------------------------------
; All 3 condition above end up here.
; This section takes the absolute value of 
; the TPS delta and limits it to $FF.
;------------------------------------------
.LDD99          subd        $0061               ; subtract top 16 bits of 24-bit TPS value from current TPS value
                std         $00CC               ; store signed throttle delta (pos or neg) in X00CC/CD
                bpl         .LDDA2              ; skip absolute value conversion if positive
                jsr         absoluteValAB       ; absolute value
.LDDA2          tsta                            ; test upper byte for zero
                beq         .LDDA7              ; branch ahead if zero
                
                ldab        #$FF                ; else load max value into B

.LDDA7          stab        $00C8               ; X00C8 is now the absolute value of TP delta ($FF max)
                cmpb        #$05                ; compare with 5
                bcc         .LDDB3              ; branch ahead if delta > 5
                
                ldaa        $008A
                oraa        #$80                ; set X008A.0
                staa        $008A

.LDDB3          ldaa        $00CC               ; load signed throttle delta (MSB)
                bpl         .LDDEF              ; branch ahead if delta is positive (TPs > X0061/62)
;-----------------------------------------
; Throttle Delta is Negative (closing)
;-----------------------------------------
                ldaa        $008B               ; B holds abs of throttle delta ($FF max)
                bita        #$01                ; test X008B.0 (road speed > 4 KPH)
                bne         .LDDC3              ; branch ahead if road speed > 4 KPH
                
                ldaa        $00D3
                bita        #$40                ; test X00D3.6 (throttle_opening bit)
                beq         .LDD5D              ; if 0, throttle is steady so branch up to jump instruction
                                                ; to jump way down and reset TPS D&R to 1024

                                                ; if here, throttle delta is negative & road speed > 4 KPH
.LDDC3          ldaa        $2011               ; this value comes from last byte in fuel map data struct (usually $64)
                mul                             ; B is absolute value of TP delta (multiply A * B)
                cmpa        $14,x               ; compare upper byte of result with value from 3rd row of table
                bcs         .LDDD4              ; branch ahead if A result of (100 * B) is less than value from 3rd row
                
                ldaa        $14,x               ; otherwise get value from table again to limit the result
                ldab        $00D3
                andb        #$BF                ; clear X00D3.6 (throttle_opening bit)
                stab        $00D3
                clrb                            ; set the low byte of this 16-bit value to zero

.LDDD4          std         $00CA               ; store the 16-bit result in X00CA/CB
                subd        $C1E7               ; data value is $0200 (subtract this from 16-bit value in AB)
                bcs         .LDDE1              ; branch ahead if AB was less than $200
                
                ldd         mafDirectLo         ; resynchronize MAF high and low readings
                std         mafDirectHi
                bra         .LDDE7              ; and branch to avoid setting X008A.7

.LDDE1          ldaa        $008A
                oraa        #$80                ; set X008A.7 (this bit may indicate a large delta in TPS)
                staa        $008A

.LDDE7          ldd         $00CA               ; load the previously stored, 16-bit result (still a negative number)
                lsrd                            ; logical shift right double
                jsr         absoluteValAB       ; convert to absolute value
                bra         .LDE0F              ; branch down to common code
                
;-----------------------------------------
; Throttle Delta is Positive (opening)
;-----------------------------------------
                                                ; B holds abs of throttle delta ($FF max)
.LDDEF          ldaa        $1E,x               ; get 4th row value from table
                mul                             ; multiply delta by this value (16-bit result in AB)
                cmpa        $0A,x               ; compare with 2nd row value for limiting reasons
                bcs         .LDDF9              ; if upper byte A is < table value we're OK so branch ahead
                
                ldaa        $0A,x               ; limit the value, read the upper byte again
                clrb                            ; and zero the lower byte

.LDDF9          std         $00CA               ; store the 16-bit result in X00CA/CB
                subd        $C135               ; data value is $0400 (subtract this from 16-bit value in AB)
                bcs         .LDE06              ; branch ahead if AB was less than $0400
                
                ldd         mafDirectHi         ; resynchronize MAF high and low readings
                std         mafDirectLo
                bra         .LDE0C              ; and branch to avoid setting X008A.7

.LDE06          ldaa        $008A
                oraa        #$80                ; set X008A.7 (this bit may indicate a large delta in TPS)
                staa        $008A

.LDE0C          ldd         $00CA               ; load the previously stored, 16-bit result (a positive number)
                lsrd                            ; logical shift right double
;-----------------------------------------
; Back to common throttle code
;-----------------------------------------
                                                ; the next 4 lines are a 16-bit divide by 4
.LDE0F          asra                            ; arithmetic shift right (into carry)
                rorb                            ; rotate right (carry->B->carry)
                asra                            ; arithmetic shift right (into carry)
                rorb                            ; rotate right (carry->B->carry)
                
                addd        #$0400              ; AB is now a pos or neg value to be added to the 1024 base value
                std         $005D               ; store TPS Dir & Rate at X005D/5E  (1024 +/-)

;-------------------------------------------------------------------------------
;                   Calculate 24-bit Throttle Pot Value
;
; X0061/62/63 is a 24-bit value that looks very much like the throttle pot
; value (X005F/60) but scaled up by 256
;-------------------------------------------------------------------------------
                ldab        $00CC               ; still the MSB of the signed throttle delta
                bpl         .LDE1F              ; branch if plus (throttle opening)
                
                ldab        #$0A                ; load number of columns in table
                abx                             ; add row to table index

.LDE1F          ldab        $00C8               ; X00C8 is abs of TP delta
                ldaa        $28,x               ; get value from 5th or 6th table row
                mul                             ; mpy TP delta abs by table value
                std         $00C8               ; store result in X00C8/C9
                ldd         $0062               ; load top 16 bits of 24-bit TP value
                tst         $00CC               ; check if TPS delta is pos or neg
                bpl         .LDE37              ; branch if positive
                
                                                ; <-- TP delta is negative
                subd        $00C8               ; subtract the just calculated value
                std         $0062               ; store the bottom 16 bits
                ldaa        $0061               ; load the top byte of 24-bit value
                sbca        #$00                ; subtract carry from top byte
                bra         .LDE3F

                                                ; <-- TP delta is positive
.LDE37          addd        $00C8               ; add the just calculated value
                std         $0062               ; store the bottom 16 bits
                ldaa        $0061               ; load the top byte of 24-bit value
                adca        #$00                ; add carry to top byte

.LDE3F          staa        $0061               ; store the top byte of 24-bit value
                ldaa        $0085               ; bits value
                ldab        $008A               ; test X008A.7 (large_difference bit)
                bpl         .LDE4B              ; branch if 0 to clear X0085.3
                
                oraa        #$08                ; set X0085.3
                bra         .LDE4D

.LDE4B          anda        #$F7                ; clr X0085.3

.LDE4D          staa        $0085               ; store bits value
;-------------------------------------------------------------------------------
;    Do stuff based on eng RPM and TP direction
;-------------------------------------------------------------------------------
                ldaa        ignPeriod           ; load ignition period MSB
                cmpa        #$09                ; compare with $09
                bcc         .LDE62              ; branch ahead if engine speed < 3255 RPM
                ldd         $005D               ; load TPS Direction & Rate (value is 1024 +/-)
                subd        #$0400              ; subtract 1024
IF BUILD_R3365
                bcc         .LDE70A
ELSE
                bcc         .LDE79              ; branch if > 1024 (opening)
ENDC                
                
                bra         .LDE70              ; else branch down (closing)

;-------------
; Unused code
;-------------
                ldd         throttlePot
                std         $0061               ; secondary throttle pot value location

;--------------------------------------------------------
                                                ; branches here if eng speed < 3255 RPM
.LDE62          ldd         throttlePot         ; load 10-bit TPS value
                subd        #$0267              ; subtract 615 (60% or 3.0 volts)
                
IF BUILD_R3365
                bcs         .LDE70A
ELSE
                bcs         .LDE79              ; branch TPS D&R > 1024 (throttle opening)
ENDC                
                
                ldd         $005D               ; load TPS Direction & Rate (1024 +/-)
                subd        #$0400              ; subtract 1024
IF BUILD_R3365
                bcc         .LDE70A
ELSE
                bcc         .LDE79              ; branch TPS D&R > 1024 (throttle opening)
ENDC                
                
;--------------------------------------------------------
.LDE70          ldd         #$0400              
                std         $005D               ; reset TPS D&R to 1024
                ldd         throttlePot         ; load TPS value
                std         $0061               ; store as top 16 bits of 24-bit value


IF BUILD_R3365
;-----------------------------------------------------------
; Defender Only (R3365)
;-----------------------------------------------------------

.LDE70A	   	    ldaa	    $007A               ; load ignition period MSB
	   	        cmpa	    #$08                ; about 3662 RPM
	   	        bcc	        .LDE79              ; branch ahead if LT 3662 RPM
	   	        ldaa	    #$27                ; dhb
	   	        staa	    AdcControlReg1
	   	        ldaa	    #$C8
	   	        staa	    AdcDataLow
	   	        jsr	        LFA46
ENDC


                
;---------------------------------------------------------------------------------------------
;						Trigger ADC Conversion on O2 Sensor
;---------------------------------------------------------------------------------------------
.LDE79          ldaa        #$8C                ; load ADC control value for right O2 sensor
                tst         $0088               ; test X0088.7 (bank indicator bit)
                bpl         .LDE82              ; branch ahead if right
                ldaa        #$8F                ; load ADC control value for left O2 sensor

.LDE82          staa        AdcControlReg1      ; start ADC conversion
                ldd         mafDirectHi         ; load MAF high
                addd        mafDirectLo         ; add  MAF low
                std         $00C8               ; X00C8/C9 = MAF sum

;------------------------------------------------------------------------------
;         Test for TPS or MAF Failure (Fault Codes 12, 18 & 19) 
;
; This code section starts executing after X008C.1 is set. This bit is set
; after the X009D/9E location counts down to zero. This 16-bit location is
; initialized to $C0 (192 decimal) and counts down at the rate of spark
; interrupts, which is just 2 or 3 seconds.
;
; This uses engine speed, throttle pot and air flow to determine either TPS
; or MAF fault. Note that later versions of this code have had the thresholds
; adjusted (desensitized) so the following LR quote is not totally accurate.
;
; According to Land Rover Document:
;
;   Typical MAF output voltage at idle is between 1.3 and 1.5 VDC (roughly 30%)
;   A diagnostic trouble code (12) is produced if MAF voltage is:
;        * less than 122 mV with RPM in excess of crank speed.
;        * greater than 4.96 V with RPM less than 976 for more than 160 mSec
;
;------------------------------------------------------------------------------

                ldaa        $008C
                bita        #$02                ; test X008C.1 (timeout bit)
                beq         .linearizeMaf       ; branch to skip test if still zero

                ldd         ignPeriod           ; load 16-bit ignition period
                subd        #$0753              ; test for 4000 RPM
                bcs         .linearizeMaf       ; skip to skip test if RPM > 4000

                ldd         $00C8               ; X00C8/C9 is sum of 2 air flow values
                subd        #$0599              ; equivalent to 70% (3.5 volt average)
                bcc         .LDEB7              ; branch ahead if airflow > 70%
                
IF BUILD_R3360_AND_LATER
                clr         $202F               ; fail delay counter (not in TVR code)
ENDC                

                ldd         $00C8               ; reload air flow sum
                subd        #$0199              ; subtract 409 dec or 1.0 volt average
                bcc         .LDED2              ; branch ahead if airflow > 1.0 volt average

                ldd         throttlePot         ; load 10-bit TPS value
                subd        #dtc18_tpsMaximum   ; 1.5 Volts in older code, 4.0 Volts in later code
                bcs         .LDED2              ; branch ahead if TPS is less than this

                ldaa        #$01                ; <-- Set Fault Code 18
                jsr         setTempTPFaults     ; (TPS > 4.0 Volts and MAF < 1.0 volt)
                bra         .LDED2              ; branch ahead

.LDEB7          ldd         throttlePot         ; load TPS value
                subd        #$00CD              ; subtract 205 dec or 1.0 volt
IF BUILD_R3360_AND_LATER                
                bcc         .LDECF              ; branch ahead if TPS > 1.0 volt
ELSE
                bcc         .LDED2              ; branch ahead if TPS > 1.0 volt
ENDC                

IF BUILD_R3360_AND_LATER
                ldaa        $202F
                inca                            ; increment fail delay counter
                staa        $202F
                cmpa        #$20                ; compare with $20
                bcs         .LDED2              ; don't set failure until counter reaches $20
                
                ldaa        faultBits_4A
                oraa        #$40                ; <-- Set Fault Code 19
                staa        faultBits_4A        ;   (TPS low with MAF high)

.LDECF          clr         $202F               ; clear the fault delay counter

ELSE
		        ldaa	    #$02                ; pass $02 to subroutine
		        jsr		    setTempTPFaults	    ; (older code only)
ENDC


.LDED2          ldaa        ignPeriod           ; load ignition period (MSB only)
                cmpa        #ignPeriodEngStart  ; test for 500 RPM (375 for cold weather chip)
                bcc         .linearizeMaf       ; skip to next section if RPM lower than this
                
                ldd         $00C8               ; reload air flow sum
                subd        #$0050              ; subtract 80 decimal (about 195 mV)
IF BUILD_R3360_AND_LATER
                bcs         .LDEEA              ; branch to increment fault delay counter if less than 195 mV
ELSE
                bcs         .LDE2A              ; branch to increment fault delay counter if less than 195 mV
ENDC                                
                subd        #$07A0              ; subtract 1952 from MAF sum (this totals 4.96 mV)
                bcs         .linearizeMaf       ; skip to next section if MAF < 4.96 mV
                
                ldaa        ignPeriod           ; load ignition period (MSB only)
                cmpa        #$1E                ; compare with 977 RPM
                bcs         .linearizeMaf       ; skip to next section if RPM > 976

IF BUILD_R3360_AND_LATER

.LDEEA          ldaa        $2034               ; load counter
                inca                            ; increment the counter
                staa        $2034               ; store it
                cmpa        #$20                ; compare it with $20
                bcs         .calcFilteredPW     ; if less, branch down to skip linearizeMaf
                
                ldaa        faultBits_49
                oraa        #$40                ; <-- Set Fault Code 12 (MAF Sensor Fault)
                staa        faultBits_49
                ldaa        $0087
                oraa        #$02                ; set X0087.1 (prevents closed loop)
                staa        $0087
                bra         .calcFilteredPW     ; branch down to skip linearizeMaf
ELSE
.LDE2A	        ldaa	    #$FF                ; pass $FF to fault subroutine
	            jsr		    setTempTPFaults
	            bra		    .calcFilteredPW     ; branch down to skip linearizeMaf

ENDC

;------------------------------------------------------------------------------
;                         MAF Sensor Linearization 
;
; This section executes unless the MAF failure bit is set. It linearizes the
; MAF output and stores the 16-bit result (normally in X204D/4E) for later use
; in determining the fuel map row (load based) index.
;
; The MAF reads about 300 decimal at idle and the maximum possible value is
; 1023 decimal (10 bits). This results in a linearized range of approximately
; 600 at idle to slightly over 17,000 decimal.
;
; The loop part of this code is a squaring function:
;       Input:      16-bit value in AB
;       Output:     (AB * AB) / 0x10000
;
; When entering this section of code, 0x00C8/C9 holds the sum of MAF Low and
; MAF High. The squaring loop is run twice. The 'C' code equivalent of the
; whole code section is listed here:
;
;       x = 8 * mafSum + 8797;
;       x = (UINT16)((x * x) / 0x10000);
;       x = (UINT16)(2 * (2 * x - 2496));
;       x = (UINT16)((x * x) / 0x10000);
;       Store result in 00CA/CB for use in 16-bit mpy (for FM row index calc)
;       Store result in 004D/4E for use elsewhere
;
;------------------------------------------------------------------------------
IF BUILD_R3360_AND_LATER
.linearizeMaf   clr         $2034               ; clear fault delay counter (newer code))
                ldd         $00C8               ; reload MAF sum
ELSE
.linearizeMaf   ldd         $00C8               ; reload MAF sum
ENDC                
                asld                            ; 2x
                asld                            ; 4x
                asld                            ; 8x
                addd        $C1C3               ; data value is $225D (8797 dec)

.linMafLoop     staa        $00C8               ; squaring function starts here
                mul
                staa        $00C9
                ldaa        $00C8
                tab
                mul
                addb        $00C9
                adca        #$00
                addb        $00C9
                adca        #$00                ; squaring function ends here
                
                com         $00CE               ; previously cleared at code address LDCEB
                beq         .LDF30              ; 1's comp forced branch out here on 2nd pass
                asld
                subd        $C1C5               ; data value is $09C0 (2496 dec)
                bcc         .LDF2D
                ldd         #$0000              ; if negative, limit to zero

.LDF2D          asld
                bra         .linMafLoop         ; end loop

.LDF30          std         $00CA               ; store it here for 16-bit mpy
                std         mafLinear           ; also store it in normal location

;---------------------------------------------------------------------------------------------------
;                         Calculate Filtered Ignition Period
;
; The instantaneous ignition period is stored in X007A/7B and the filtered ignition period is
; stored in X007C/7D. The filtered value is calculated by summing 1 part instantaneous and
; 3 parts filtered, then dividing by 4. The code below also guards against 16-bit rollovers by
; incrementing X00CC and then shifting these bits back in. Normally there is no rollover since
; we need to be below 500 RPM for this to happen.
;---------------------------------------------------------------------------------------------------
.calcFilteredPW ldd         #$0003              ; load double value $0003
                std         $00CC               ; X00CC = $00,  X00CD = $03
                ldd         ignPeriod           ; load 16-bit ignition period (instantaneous)
                
                                                ; * start 3X loop *
.LDF3C          addd        ignPeriodFiltered   ; add  16-bit ignition period (filtered) 
                bcc         .LDF43              ; branch ahead if sum did not roll over
                inc         $00CC               ; increment X00CC when rollover happened
.LDF43          dec         $00CD               ; decrement loop counter
                bne         .LDF3C              ; * end 3X loop *

                lsr         $00CC               ; lsb into carry
                rora                            ; carry into msb, lsb into carry
                rorb                            ; carry into msb
                lsr         $00CC               ; lsb into carry
                rora                            ; carry into msb, lsb into carry
                rorb                            ; lsb into carry
                std         ignPeriodFiltered   ; store filtered ignition period

;---------------------------------------------------------------------------------------------------
;                *** Calculate Fuel Map Load Value (Row Index) ***
;
; This value, which is normally stored at X005B, is calculated from both air flow and engine speed.
;
; The Linearized MAF is calculated above and is stored in the normal X004D/4E locations and the
; X00CA/CB temporary location.
;
; The row index value is clipped low at 0x00 and high at 0x70 so that it is confined to the range
; of the 8 row fuel map table.
;   
;---------------------------------------------------------------------------------------------------
                ldd         ignPeriod           ; load 16-bit ignition period (instantaneous)
                jsr         mpy16               ; call 16-bit mpy routine, mpy ignPeriod by mafLinear
                subd        $C1C7               ; data value is $001E (subtract this)
                bcc         .LDF61              ; branch ahead if value is still positive
                clra                            ; else, clear A
                bra         .LDF6F              ; and branch

.LDF61          lsrd                            ; logical shift right double
                tsta                            ; test A for zero
                bne         .LDF6D              ; branch ahead to load $70
                ldaa        $200A               ; X200A gets initialized from fuel map byte offset $10A
                mul
                cmpa        #$70                ; compare A with $70
                bcs         .LDF6F              ; if A <= $70, branch to store as fuel map row index

.LDF6D          ldaa        #$70                ; else store $70

.LDF6F          staa        fuelMapLoadIdx      ; store value as 'fuelMapLoadIdx'

;---------------------------------------------------------------------------------------------------
;                             Check for Neutral Switch Fault 
;
;	This is done by first making sure that the vehicle is not a manual transmission, then if the
;   engine RPM and air flow both indicate that the vehicle should be moving and park is indicated,
;   a counter is incremented. After 500 counts, the Neutral Switch Fault Bit is set.
;
;   The following is the from Land-Rover document titled "13/14CU AND 14CUX SYSTEMS"
;
;	"A diagnostic trouble code (69 [14CUX only]) is set when sensor voltage is 5 V during cranking
;   or 0 V with RPM above 2663 and MAFS voltage above 3V."
;
;   Note that although this document was written late (1995 or later) and mentions the fact that
;   fault trigger thresholds were frequently changed, the actual quoted thresholds were never
;   updated. For example, very old PROMs (such as R2157) initially used $0B00 for the RPM threshold.
;   This agrees with the value 2663 mentioned above. However, this threshold was later changed to
;   $0E00 (2093 RPM), which appears in TVR PROMs, and then to $1000 (1831 RPM) in the latest code.
;
;   X008A.5 is 0 for neutral/park/manual and 1 for automatic in drive (ADC service)
;   X2004.1 is set to 1 for manual gearbox (mid-level value at ADC) (idleControl)
;
;---------------------------------------------------------------------------------------------------
                ldab        $2004               ; 2004 is used as bits
                bitb        #$02                ; test X2004.1 (bit is set for manual gearbox)
                bne         .LDFA3              ; if set, branch to clear counter and return
                
                ldab        ignPeriod           ; ignition period (MSB)
                cmpb        #dtc69_rpmMinimum   ; compare wuth $0E (2093 RPM) later: $10 (1831 RPM)
                bcs         .LDFA3              ; branch to clr counter and return if RPM is higher
                
                cmpb        #$13                ; compare with $13 (1541 RPM)
                bcc         .LDFA3              ; branch to clr counter and return if RPM is lower
IF BUILD_R3360_AND_LATER                
                ldab        neutralSwitchVal
                cmpb        #$B3                ; this value or higher indicates automatic in drive
                bcc         .LDFA3              ; branch to clr counter and return if drive indicated
ELSE
			    ldab	    $008A
			    bitb	    #$20                ; test X008A.5, if set, drive is indicated
			    bne	        .LDFA3              ; if set, branch to clr counter and return
ENDC                            
                cmpa        #$60                ; compare fuel map load index with $60
                bcs         .LDFA3              ; branch to clr counter and rtn if load index < $60
                
                ldd         $203F               ; this is the 16-bit neutral fault delay counter
                addd        #$0001              ; add 1
                std         $203F               ; store it
                subd        #$01F4              ; subtract 500 decimal
                bcs         .LDFA8              ; branch to next section if counter < 500
                
                ldaa        faultBits_4C
                oraa        #$80                ; <-- Set Fault Code 69 (Neutral Switch Fault)
                staa        faultBits_4C
                bra         .LDFA8

.LDFA3          clra 
                clrb
                std         $203F               ; reset counter to zero

;---------------------------------------------------------------------------------------------------
;                          This section of code is still a mystery
;
;    X00E0 is related to X2055/56 (right bank)
;    X00E1 is related to X2057/58 (left bank)
;    X00E0 and X00E1 may be counters for something bad (like misfires) and are usually zero
;    X2055/56 and X2057/58 are referenced only here
;---------------------------------------------------------------------------------------------------
.LDFA8          ldaa        $00E0               ; load right bank value
                bne         .LDFB2              ; branch if not zero
                
                ldd         #$0000              ; reset X2055/56 right bank value to zero
                std         $2055               ; 

.LDFB2          ldaa        $00E1               ; load left bank value
                bne         .LDFBC              ; branch if not zero
                
                ldd         #$0000              ; reset X2057/58 left bank value to zero
                std         $2057               ;

.LDFBC          ldd         $2057               ; load 16-bit value
                addd        #$0001              ; add 1
                std         $2057               ; store it
                ldd         $2055               ; load 16-bit value
                addd        #$0001              ; add 1
                std         $2055               ; store it

                                                ; data value at XC25D is $0258 (600 decimal)
                subd        $C25D               ; subtract 600 from X2055/56
                bcs         .LDFD6              ; branch if value is less than 600
                
                clr         $00E0               ; else clear X00E0

.LDFD6          ldd         $2057               ; load X2057/58
                subd        $C25D               ; subtract 600
IF BUILD_TVR_CODE
                bcs         .LDF0B              ; if value < 600, branch to next section (TVR)
ELSE
                bcs         .LDFE1              ; if value < 600, branch to next section
ENDC
                clr         $00E1               ; else clear X00E1


IF BUILD_TVR_CODE
                ; nothing
                
ELSE

                ; NOTE: This whole section is missing from older code.      
;---------------------------------------------------------------------------------------------------
;       In this section, a couple of bits are managed that can prevent closed loop operation
;
;
;    X205B.2 is set when:
;        - Road speed is greater than 4 KPH, AND
;        - X0086.7 is set (set & clrd in TPS routine) AND
;        - Coolant temperature is cooler than 83 degrees C
;    Bit is cleared if any 1 condition is not met
;
;    X205B.5 is set when:
;        - X0086.7 is set (set & clrd in TPS routine) AND
;        - X008A.5 is clr (neutral or D90, not drive) AND
;        - Road speed is less than 4 KPH, AND
;        - Coolant temperature is cooler than 40 degrees C
;    Bit is cleared if any 1 condition is not met
;
;---------------------------------------------------------------------------------------------------
.LDFE1          ldab        $205B               ; bits value
                ldaa        $008B               ; slao a bits value
                bita        #$01                ; test X008B.0 (road speed > 4 KPH)
                beq         .LDFFA              ; branch ahead if road speed < 4 KPH

                tst         $0086               ; test X0086.7
                bpl         .LDFFA              ; branch ahead if X0086.7 is zero
                
                ldaa        coolantTempCount    ; load ECT sensor count
                cmpa        $C170               ; data value is $27 (83 degrees C)
                bcs         .LDFFA              ; branch ahead if ECT is hotter than this
                
                orab        #$04                ; set X205B.2 (prevents closed loop)
                bra         .LDFFC              ; branch

.LDFFA          andb        #$FB                ; clr X205B.2 (allows closed loop)

.LDFFC          stab        $205B               ; store bits value

;---------------------------------------
IF BUILD_R3383
                ; nothing          
ELSE                

                ldab        $205B               ; reload to set CCR
                tst         $0086               ; test X0086.7
                bpl         .LE01E              ; branch ahead if X0086.7 is zero
                
                ldaa        $008A               ; load bits value
                bita        #$20                ; test X008A.5 (neutral switch)
                bne         .LE01E              ; branch if 1 (automatic in drive)
                
                ldaa        $008B
                bita        #$01                ; test X008B.0 (road speed > 4 KPH)
                bne         .LE01E              ; branch if road speed is > 4 KPH
                
                ldaa        coolantTempCount    ; load ECT sensor count  
                cmpa        $C7E0               ; data value is $65 (40 degrees C)
                bcs         .LE01E              ; branch ahead if ECT is hotter than this
                
                orab        #$20                ; set X205B.5 (prevents closed loop)
                bra         .LE020

.LE01E          andb        #$DF                ; clr X205B.5 (allows closed loop)

.LE020          stab        $205B               ; stor bits value

ENDC
ENDC

;---------------------------------------------------------------------------------------------------
;                        Prepare Variables for Bank-Specific Processing
;
; X00BE is a right bank value
; X00BF is a left bank value
; X00BD is a temporary "working" value for either value above
;
; This section loads X00BD with the correct bank variable and also loads the general purpose
; memory location X00C8/C9 with the short term trim value for the same bank.
; 
;---------------------------------------------------------------------------------------------------
.LDF0B          clra
                clrb
                std         $00CE               ; clear X00CE/CF to $0000
                ldaa        $0089               ; bits value
                anda        #$BF                ; clr X0089.6
                bita        #$10                ; test X0089.4 (right bank bit)
                beq         .LE031              ; branch ahead if X0089.4 is zero
                
                oraa        #$40                ; set X0089.6

.LE031          staa        $0089               ; store bits value

                ldaa        $00BE               ; load right bank value
                staa        $00BD               ; store it in X00BD (working value)
                ldd         shortLambdaTrimR    ; load right side short term trim value
                tst         $0088               ; test X0088.7 (this is the toggling bank bit)
                bpl         .LE050              ; if right bank, branch ahead to go with these values

                ldaa        $0089               ; else, prepare for left bank
                anda        #$BF                ; clr X0089.6
                bita        #$20                ; test X0089.5 (left bank bit)
                beq         .LE048              ; branch ahead if X0089.5 is zero
                
                oraa        #$40                ; set X0089.6

.LE048          staa        $0089               ; store bits value
                ldaa        $00BF               ; load left bank value
                staa        $00BD               ; store it in X00BD (working value)
                ldd         shortLambdaTrimL    ; load left side short term trim value

.LE050          std         $00C8               ; this will be either right or left short term trim

;---------------------------------------------------------------------------------------------------
;                           Read HO2 Sensor Measurement from ADC
;
; Read HO2 Sensor voltage (conversion was triggered earlier) then do numerous checks (including
; fuel map number, coolant temp, eng speed, eng load, etc.) to make sure we can do a closed loop
; adjustment. If yes, compare the HO2 reading with the reference value and branch to rich or lean.
;
; Oddly, the triggering and measurement of the HO2 (Lambda) sensors is also done for open loop
; maps. The difference is that open loop maps (1, 2 and 3) branch down to a jump instruction at
; LE0C6 which causes a lot of code to be bypassed.
;
;---------------------------------------------------------------------------------------------------
                ldab        AdcDataLow          ; read 8-bit HO2 sensor voltage here
IF SIMULATION_MODE
                jsr         o2Simulation        ; for simulation
ENDC

IF BUILD_R3365
;-----------------------------------------------------------
; Defender Only (R3365) (SIMULATION WON'T WORK WITH R3365)
;-----------------------------------------------------------
                stab        $2012               ; X2012 holds the current HO2 sensor reading

	   	        ldaa	    #$27                ; 
	   	        staa	    AdcControlReg1
	   	        ldaa	    #$C8
	   	        staa	    AdcDataLow
	   	        jsr	        LFA46

                ldab        $2012               ; X2012 holds the current HO2 sensor reading
ELSE	   	        
                stab        $2012               ; X2012 holds the current HO2 sensor reading
                jsr         rdSpdCompTest       ; road speed comparator test, reloads X2012 in B before returning
ENDC

;-----------------------------------------------------------

                ldaa        fuelMapNumber       ; load fuel map number
                beq         .LE064              ; branch if fuel map number is zero
                
                cmpa        #$04
                bcs         .LE0C6              ; branch if fuel map number is less than 4

;------------------------------------
; Closed loop maps only (0, 4 and 5)
;------------------------------------
.LE064          ldaa        $201D               ; counts down from $10 to zero (at about 1 Hz)
                bne         .LE0C6              ; if not zero, branch to same place as open loop maps
                
                ldaa        coolantTempCount    ; load ECT sensor count
                cmpa        $200F               ; from 3rd last byte in fuel map (will be $23 to $2C)
                bcs         .LE07B              ; if hotter than this, branch ahead to continue closed loop
                
                cmpa        $C1F8               ; this data value varies a lot (can be $CE or $7A)
                bcc         .LE0C6              ; if engine is cooler than this, branch to the same place as
                                                ; open maps ($CE = -5 deg C, $7A = 30 deg C)
                
                ldaa        $0086
                bita        #$04                ; test X0086.2 (1 allows closed loop, 0 forces open loop)
                beq         .LE0C6              ; if zero, branch down like an open loop map

.LE07B          ldaa        ignPeriod           ; load ignition period (MSB only)
                cmpa        #$07                ; compare upper byte of eng speed
                bcs         .LE0F0              ; if RPM > 4185, branch ahead to bypass misfire test
                
                ldaa        $008C
                bita        #$08                ; test X008C.3 (stayed zero for both RTs)
                beq         .LE0F0              ; if X008C.3 is zero, branch ahead to bypass misfire test
                
                ldaa        fuelMapLoadIdx      ; load fuel map row index
                cmpa        #$50                ; compare it with $50
                bcs         .LE0F0              ; if map load index < $50, branch ahead to bypass misfire test
                
                ldaa        coolantTempCount    ; load ECT sensor count
                cmpa        $C17E               ; from default coolant temp table, value usually $23 (87 deg C)
                bcc         .LE0F0              ; if cooler than this, branch ahead to bypass misfire test
IF BUILD_R3360_AND_LATER                
                ldaa        faultBits_49        ; (newer code only)
                bita        #$46                ; test bits 6,2,1 (MAF fault 12 and O2 faults 44 & 45)
                bne         .LE0F0              ; if any fault bits, branch ahead to bypass misfire test
ENDC                

                pshb                            ; <-- HO2 reading is pushed here
                ldd         $005D               ; load Throttle Direction & Rate value (1024 +/-)
                subd        $C25F               ; data value is $03F6 or $03E6 (1014 or 998 decimal)
                pulb                            ; <-- HO2 reading is pulled here (CCR not affected)
IF BUILD_TVR_CODE
                bcs         .LE10C              ; if throttle closing, branch to next section
ELSE
IF BUILD_R3383
                bcs         .LE10C              ; if throttle closing, branch to next section
ELSE
                bcs         .LE0F0              ; if throttle closing, branch ahead to bypass misfire test
ENDC
ENDC                
                ldaa        o2ReferenceSense    ; make rich/lean decision here for misfire test
                cba                             ; compare accums, A (reference value) minus B (HO2 reading)
                bcs         .LE0FB              ; branch if HO2 reading greater then reference value (rich)
                                                ; Wikipedia: lean mixture causes low voltage (excess oxygen)
                                                ;            rich mixture causes high voltage (depleted O2)

;---------------------------------------------------------------------------------------------------
;	Misfire Check -- Lean Condition -- (HO2 voltage is low, excess oxygen)
;
;	Check for misfire fault (40 & 50) here. A misfire results in excess (unused) oxygen.
;---------------------------------------------------------------------------------------------------
                tst         $0088               ; test X0088.7 (bank indicator bit)
                bmi         .LE0C9              ; branch ahead if bit is 1 (left bank)
;------------------
; Right Bank
;------------------
                ldaa        $00DD               ; load X00DD
                bita        #$20                ; test X00DD.5
                bne         .LE10C              ; branch to next section if bit is already set
                
                oraa        #$20                ; set X00DD.5
                staa        $00DD               ; store bit value
                ldaa        $00E0               ; load X00E0
                inca                            ; increment X00E0
                cmpa        $C1EE               ; data value is $0C (compare with X00E0 value in A)
                bcc         .LE0E2              ; branch ahead if value < $0C (to set Misfire A fault bit)
                
                staa        $00E0               ; store X00E0
                staa        $207A               ; also stored here at X207A but never used
                bra         .LE10C              ; branch to next section

;-----------------------------------------
.LE0C6          jmp         .LE523              ; jump label for skipping closed loop
;-----------------------------------------

;------------------
; Left Bank
;------------------
.LE0C9          ldaa        $00DD               ; load X00DD
                bita        #$40                ; test X00DD.6
                bne         .LE10C              ; branch to next section if bit is already set
                
                oraa        #$40                ; set X00DD.6
                staa        $00DD               ; store bits value
                ldaa        $00E1               ; load X00E1
                inca                            ; increment X00E1
                cmpa        $C1EE               ; data value is $0C (compare with X00E1 value in A)
                bcc         .LE0E8              ; branch ahead if value < $0C (to set Misfire B fault bit)
                
                staa        $00E1               ; store X00E1
                staa        $207B               ; also stored here at X207B but never used
                bra         .LE10C              ; branch to next section
;-----------------------------------------

.LE0E2          ldaa        faultBits_49
                oraa        #$10                ; <-- Set Fault Code 40 (Misfire A Fault) RIGHT SIDE!!
                bra         .LE0EC              ;

.LE0E8          ldaa        faultBits_49
                oraa        #$20                ; <-- Set Fault Code 50 (Misfire B Fault) LEFT SIDE!!

.LE0EC          staa        faultBits_49

IF BUILD_R3360_AND_LATER
                ; newer code does not use fault code 25
ELSE
			    ldaa	    $0049
			    oraa	    #$08                ; <-- set Fault Code 25 (general misfire)
			    staa	    $0049
ENDC
                bra         .LE10C              ; branch to next section
;-----------------------------------------
                                                ; code can branch here from above to bypass misfire test
.LE0F0          clra                            ; clear A
                staa        $00E0               ; set X00E0 to zero
                staa        $00E1               ; set X00E1 to zero
                ldaa        $00DD               ; load bits value
                oraa        #$60                ; set bits X00DD.6 and X00DD.5
                bra         .LE10A              ; branch ahead to store value and continue
                
;-------------------------------------------------------------------------------
;
;	Rich Condition -- (O2 voltage is high, depleted oxygen)
;
;-------------------------------------------------------------------------------
.LE0FB          tst         $0088               ; test X0088.7 (bank bit)
                bmi         .LE106              ; branch ahead if bit 7 is 1 (left bank)
                
                ldaa        $00DD               ; Right Bank
                anda        #$DF                ; clrar X00DD.5
                bra         .LE10A              ; branch to store and continue

.LE106          ldaa        $00DD               ; Left Bank
                anda        #$BF                ; clear X00DD.6

.LE10A          staa        $00DD               ; store bits value

;-----------------------------------------------------------------------------------------------------------------
;                                Make Open/Closed Loop Decision Here
;
;
;   X0087    All bits except 6 and 2 force open loop
;
;            Bit 0:  Set when MAF > 2.0 Volts AND Coolant Temp < 50 degrees C
;            Bit 1:  Set when MAF fault occurs
;            Bit 3:  Set when throttle pot is > 91% (approx 4.6 Volts)
;            Bit 4:  (otherwise unused, should be zero)
;            Bit 5:  Set when RPM > 3400 (value stored at 0xC0A7)
;            Bit 7:  Set & cleared in spark interrupt (todo)
;
;   X205B.2  When this bit is set, open loop is forced. It's set when:
;		        1) Road speed is > 4 KPH
;                    AND
;		        2) Bit X0086.7 is set
;                    AND
;		        3) Coolant temp is cooler than 83 deg C
;
;   X205B.5  When this bit is set, open loop is forced. It's set when:
;		        1) Bit X0086.7 is set
;                    AND
;		        2) Bit X008A.5 is zero (park, neutral or manual, not drive)
;                    AND
;                3) Road speed < 4 KPH
;                    AND
;		        4) Coolant temp is cooler than 40 deg C
;
;    More bits that force open loop:
;
;    X0085.7  Low engine RPM (less than 505 RPM, or 375 RPM for op-pride cold weather chip)
;    X0089.7  (todo)
;    X008C.3  (todo, bit 008C.2 seems to correlate to the open/closed condition)
;    X008A.6  Set at startup, timeout from 3rd row of coolant table (1 Hz dwn_cnt, also fueling component)
;
;    Plus a magic byte:
;
;    0xC099  Default is zero, set to non-zero to force open loop
;
;-----------------------------------------------------------------------------------------------------------------
.LE10C          ldaa        $0087               ; bits value
                anda        #$BB                ; clr X0087.6 (RPM < 1200+) and X0087.2 (not written back to X0087)
                oraa        $C099               ; this value normally zero (set no bits)
                bne         .LE15D              ; if non-zero, branch to jmp to LE523 (skip closed loop)
                               
IF BUILD_TVR_CODE
                ; nothing
ELSE                
                ldaa        $205B               ; bits value
                bita        #$04                ; test X205B.2
                bne         .LE15D              ; if set, branch to jmp to LE523 (skip closed loop)
IF BUILD_R3383
                ; nothing
ELSE                
                bita        #$20                ; test X205B.5
                bne         .LE15D              ; if set, branch to jmp to LE523 (skip closed loop)
ENDC                
ENDC
                ldaa        $0085               ; bits value (X0085.7 indicates low eng RPM)
                oraa        $0089               ; or with bits value X0089 (tests X0089.7)
                bmi         .LE15D              ; if either bit 7 is set, branch to jmp to LE523 (skip closed loop)
                
                ldaa        $008C               ; bits value
                bita        #$08                ; test X008C.3
                bne         .LE15D              ; if set, branch to jmp to LE523 (skip closed loop)
                
                ldaa        $008A               ; bits value
                bita        #$40                ; test X008A.6 (set at startup, cleared after timeout)
                bne         .LE15D              ; if set, branch to jmp to LE523 (skip closed loop)
                
                ldaa        $00D3               ; bits value
                tst         $0088               ; test X0088.7 (bank indicator)
                bmi         .LE13D              ; branch ahead if bit 7 is 1 (left bank)
                
                bita        #$01                ; Right Bank,  test X00D3.0 (right bank O2 sensor fault)
                bra         .LE13F              ; 

.LE13D          bita        #$02                ; Left Bank, test X00D3.1 (left bank O2 sensor fault)

.LE13F          bne         .LE15D              ; if either fault bit set, branch to skip closed loop

                ldaa        $008D               ;
                bita        #$11                ; test X008D.4 and X008D.0
                bne         .LE160              ; if either bit set, branch to continue closed loop
                
                ldaa        $0088               ; test bank indicator bit
                bmi         .LE151              ; branch ahead if bit 7 is 1 (left bank)
                
                bita        #$40                ; Right Bank, test X0088.6 (a right bank bit)
                bne         .LE157              ; if bit set, branch->jmp->E5EA
                bra         .LE160              ; branch to continue closed loop

.LE151          bita        #$20                ; Left Bank, test X0088.5 (left bank bit)
                bne         .LE157              ; if bit set, branch->jmp->E5EA
                bra         .LE160              ; branch to continue closed loop
;-----------------------------------------

.LE157          jmp         .LE5EA              ; jumps down further than closed loop (skips purge valve)
;-----------------------------------------
                jsr         LF3A3               ; <-- non-accessed code
;-----------------------------------------

.LE15D          jmp         .LE523              ; jumps to same point as open loop maps

;------------------------------------------------------------------------------
;                       Start of Closed Loop Code
;
;
; X00C8/C9 holds the 16-bit short term trim (either right or left)
; B accumulator holds the HO2 sensor reading (same bank)
;
;------------------------------------------------------------------------------
.LE160          pshb                            ; push HO2 sensor reading
                ldaa        $2020               ; right bank startup timer (init to 3, decrements at 1 Hz)
                bne         .LE181              ; branch to jump if X2020 is not zero
                
                ldaa        $2021               ; left bank startup timer (init to 3, decrements at 1 Hz)
                bne         .LE181              ; branch to jump if X2021 is not zero
                
                ldx         #$008E              ; X008E = right, X008F = left
                ldaa        $0089               ; bits value
                anda        #$07                ; mask low 3 bits
                beq         .LE184              ; branch only if all 3 are zeros
                
                bita        #$03                ; test bits 1 and 0 only
                bne         .LE181              ; branch to jump if either bit is set
                
                ldaa        $0089               ; bits value
                anda        #$F8                ; clear low 3 bits
                staa        $0089               ; store it

.LE17E          jmp         .LE21A              ; jump down to 'jsr' before rich/lean code
;-----------------------------------------
.LE181          jmp         .LE21D              ; jump down to rich/lean code

;-----------------------------------------
.LE184          ldd         mafDirectHi         ; load MAF high
                addd        mafDirectLo         ; add MAF low
                subd        $C1AF               ; subtract $043D (1085d) from air flow sum (2.65V avg)
                bcs         .LE17E              ; bra->jmp->LE21A if air flow sum is less than this value
                
                subd        $C1B2               ; air flow is higher so subtract an additional $0100
                bcc         .LE17E              ; bra->jmp->LE21A if air flow is higher (3.28V avg)

                                                ; if here, MAF avg is between 2.65V and 3.28V
                ldaa        coolantTempCount    ; load ECT sensor count
                cmpa        $C17E               ; inside coolant temp table (value is $23 or 87 deg C)
                bcc         .LE17E              ; bra->jmp->LE21A if temperature cooler than 87 C
                
                ldd         $0094               ; this loads right counter in A and left counter in B
                tst         $0088               ; test X0088.7 (bank indicator)
                bpl         .LE1AB              ; branch ahead if bit 7 is 0 (right bank)
                
                inx                             ; Left Bank, so increment X from X008E to X008F
                ldaa        $00AB               ; load MSB of 16-bit left bank value
                cmpb        $C1B1               ; compare value $15 with value from X0095
                bcc         .LE1B2              ; branch ahead if X0095 is > $15

.LE1A8          jmp         .LE21D              ; jump ahead (when X0094 or X0095 is < $15)

.LE1AB          cmpa        $C1B1               ; Right Bank, compare value $15 with value from X0094
                bcs         .LE1A8              ; bra->jmp->LE21D if X0094 is LT $15
                
                ldaa        $00A9               ; load MSB of 16-bit right bank value

;------------------------------------------------------------------------------
; This code is executed when X0094 (right) or X0095 (left) is greater than $15
;
; A accum contains MSB of X00A9/AA or X00AB/AC
; Index contains #008E or #008F
; Table at $C196 is used, top row values for this table are not temperatures.
;
; This is fault condition code and not normally executed.
;------------------------------------------------------------------------------
.LE1B2          ldab        $02,x               ; X is X008E or X008F so loading X0090 or X0091
                stab        $00CA               ; store it in temporary location
                ldab        $00,x               ; load X008E or X008F
                pshx                            ; push the index value
                pshb                            ; push B (value from X008E or X008F)
                ldab        #$08                ; table at XC196 is 8 columns wide
                ldx         #$C196              ; address of 3-row data table
                jsr         indexIntoTable      ; index into table
                ldaa        $08,x               ; load value from 2nd row of table
                ldab        $10,x               ; load value from 3rd row of table (all zeros)
                bne         .LE1D0              ; all zeros so never branches
                
                ldab        $00CA               ; value from X0090 or X0091
                mul                             ; multiply this value by 2nd row value
                staa        $00CA               ; save MSB only
                pulb                            ; pull the value from X008E thru X0091
                bra         .LE1D3              ; branch

                                                ; this option not normally used
.LE1D0          pulb                            ; pull the value from X008E thru X0091
                mul                             ; multiply B by 2nd row value
                tab                             ; transfer MSB of result into B

.LE1D3          clra                            ; clear A
                subb        $00CA               ; subtract value in X00CA
                pulx                            ; pull the pointer to X008E through X0091
                bcc         .LE1EE              ; branch ahead if X00CA was less than B

                ldaa        #$FF                ; it's a negative number
                jsr         absoluteValAB       ; convert to absolute value (A should now be zero)

                cmpb        $C1AE               ; data value is $01
                bcs         .LE1FC              ; branch if B < $01
                
                ldab        $04,x               ; value from X0092 or X0093 (are these signed numbers?)
                cmpb        #$05                ; compare with 5
                beq         .LE1FC              ; branch ahead if value is exactly 5
                
                incb                            ; if not, increment and
                stab        $04,x               ;   store the value
                bra         .LE1FC              ; and branch

.LE1EE          cmpb        $C1AE               ; compare X0092 or X0093 with value of $01
                bcs         .LE1FC              ; branch ahead if it was less than 1
                
                ldab        $04,x               ; value from X0092 or X0093
                cmpb        #$FB                ; compare with minus 5 (signed number)
                beq         .LE1FC              ; branch ahead if value is minus 5
                
                decb                            ; if not, decrement and
                stab        $04,x               ;  store the value

.LE1FC          addb        #$05                ; add 5
                cmpb        #$0A                ; compare with 10
                bls         .LE205              ; branch if lower or same
                
                clrb                            ; clear B
                stab        $04,x               ; clear the value at X0092 or X0093

.LE205          clra                            ; clear A
                tab                             ; transfer A to B
                staa        $00,x               ; clear X008E or X008F
                staa        $02,x               ; clear X0090 or X0091
                staa        $06,x               ; clear X0094 or X0095
                tst         $0088               ; test 0088.7 (bank indicator)
                bpl         .LE216              ; branch ahead if bit is 0 (right bank)
                
                std         $00AB               ; Righ Bank: clear X00AB/AC
                bra         .LE21D              ; branch to next section


.LE216          std         $00A9               ; Right Bank: clear X00A9/AA
                bra         .LE21D              ; branch to next section
;------------------------------------------------------------------------------

.LE21A          jsr         LF3C0               ; code can jump here from above (this routine clears some vars)

;---------------------------------------------------------------------------------------------------
;						        Determine if Rich or Lean
;
; X201B (right) and X201C (left) are offset or bias values that are added to the threshold value
; The data value XC098 (usually zero) is also added/subtracted as an addition bias.
;
; From Wikipedia:   lean mixture causes low voltage (excess oxygen)
;                   rich mixture causes high voltage (depleted O2)
;
;---------------------------------------------------------------------------------------------------
.LE21D          pulb                            ; pull the HO2 reading reading
                ldaa        $00BD               ; this is working value from X00BE (right) or X00BF (rt)
                bne         .LE23A              ; branch if value is not zero
                
                ldaa        o2ReferenceSense    ; load the HO2 threshold value
                tst         $0088               ; test bank indicator bit
                bmi         .LE22E              ; branch ahead if bit is 1 (left bank)
                
                adda        $201B               ; Right:  add X201B to HO2 reference value
                bra         .LE231

.LE22E          adda        $201C               ; Left: add X201C to HO2 reference value

.LE231          cba                             ; A (ref plus X201B or X201C) minus B (HO2 reading)
                bcs         .LE243              ; branch if HO2 reading is higher than reference value
                
                suba        $C098               ; Lean: data value is zero, subtract from reference
                cba                             ; result still positive, since value is zero
                bcc         .LE25A              ; branch to jmp to lean_condition code

.LE23A          ldaa        $0089               ; code jumps here if X00BD value is non-zero
                bita        #$40                ; test X0089.6
                beq         .LE2B0              ; if zero, branch to jump to LE459 (into lean code)

.LE240          jmp         .LE2EF              ; jump down (into rich_condition code)
;--------------------------------------------------
.LE243          adda        $C098               ; Rich: data value is zero (A = ref + 201x + XC098)
                cba                             ; A - B again (same result, carry set, so continue))
                bcc         .LE23A              ; 
                
;------------------------------------------------------------------------------
;    Rich Condition (Depleted Oxygen, High Voltage)
;------------------------------------------------------------------------------
                ldaa        $00D2               ; bits value (all bits are bank specific)
                tst         $0088               ; test bank indicator bit
                bmi         .LE25D              ; branch ahead if 1 (left bank)
;--------------
; Right Bank
;--------------
                bita        #$04                ; test X00D2.2
                beq         .LE267              ; if zero, branch to common bank code below
                
                oraa        #$40                ; set  X00D2.6
                anda        #$FB                ; clr  X00D2.2
                bra         .LE265              ; branch to store X00D2 and enter common code
;------------------------------------------

.LE25A          jmp         .LE3B3              ; jump down to lean_condition code (label is used above)

;--------------
; Left Bank
;--------------
.LE25D          bita        #$08                ; test X00D2.3
                beq         .LE267              ; if zero, branch to common bank code below
                
                oraa        #$80                ; set  X00D2.7
                anda        #$F7                ; clr  X00D2.3

;--------------
; Common Code
;--------------
.LE265          staa        $00D2               ; store X00D2 bits value

.LE267          ldaa        $0089               ; if bit 2 or bit 3 is zero
                bita        #$40                ; test X0089.6                
                bne         .LE240              ; if bit 6 is 1, branch to above jump
                
                oraa        #$40                ; set X0089.6
                staa        $0089               ; store X0089
                anda        #$07                ; mask low 3 bits
                bne         .LE278              ; branch ahead if X0089 bit 2, 1 or 0 set
                
                jsr         LF1D4               ; this subroutine uses MAF readings

.LE278          jsr         LF416               ; this subroutine manipulates bits in X00E2
                ldaa        $C097               ; data value is $04
                staa        $00BD               ; working value for X00BE or X00BF
                ldaa        $2004               ; load bits value
                tst         $0088               ; test bank indicator bit
                bmi         .LE28C              ; branch ahead if 1 (left bank)
                
                oraa        #$04                ; Right:  set X2004.2
                bra         .LE28E              ; 

.LE28C          oraa        #$08                ; Left: set X2004.3

.LE28E          staa        $2004               ; store X2004
                ldaa        $0089               ; load bits value
                anda        #$02                ; test X0089.1
                beq         .LE29B              ; branch ahead if bit is zero
                
                ldd         $0090               ; lean condition code uses 0x008E here
                bra         .LE29C              ; branch

.LE29B          tab                             ; transfer A to B

.LE29C          psha                            ; push A to stack
                ldaa        $205B               ; load bits value
                tst         $0088               ; test bank indicator bit
                bpl         .LE2B3              ; branch ahead if 0 (right bank)
;--------------
; Left Bank
;--------------
                bita        #$02                ; test X205B.1
                beq         .LE2C9              ; branch is bit is zero
                
                anda        #$FD                ; clear X205B.1
                staa        $205B               ; store it
                bra         .LE2BC              ; branch
                
;---------------------------------------
.LE2B0          jmp         .LE459              ; jump down into lean_condition code (used above)
;---------------------------------------

;--------------
; Right Bank
;--------------
.LE2B3          bita        #$01                ; test X205B.0
                beq         .LE2C9              ; branch if bit is zero
                
                anda        #$FE                ; clear X205B.0
                staa        $205B               ; store it

;--------------
; Common Code
;--------------
.LE2BC          clr         $00CE               ; clear X00CE to zero
                ldaa        $C096               ; data value is $40
                staa        $00CF               ; store it in X00CF (used later)
                pula                            ; pull A from stack (MSB of X0090)
                addd        $00CE               ; add X00CE
                bra         .LE2E1              ; branch

.LE2C9          pula                            ; pull A from stack (MSB of X0090)
                tst         $0086               ; test X0086.7
                bpl         .LE2DC              ; branch ahead if X0086.7 is zero
                
                psha                            ; push A
                ldaa        $008B               ; load X008B
                anda        #$01                ; mask X008B.0 (road speed > 4 KPH)
                pula                            ; pull A
                bne         .LE2DC              ; branch if road speed > 4 KPH
                
                ldx         #$C7D3              ; lean code below uses XC7D1 (both are 4000 decimal)
                bra         .LE2DF              ; branch

.LE2DC          ldx         #$C094              ; lean code below uses XC092 (both are 8000 decimal)

.LE2DF          addd        $00,x               ; add 8000 decimal

.LE2E1          std         $00CE               ; store this value in temporary location
                ldd         $00C8               ; still the short-term lambda trim value from earlier?
                subd        $00CE               ; subtract 16-bit
                bra         .LE33B              ; branch
                
;--------------------------------------------------
.unused2        jmp         .LE459              ; unused code
;--------------------------------------------------
.unused3        jmp         .LE3B3              ; unused code
;--------------------------------------------------
.LE2EF          jsr         LF224               ; subroutin decrements value in X00BD if not zero
                ldaa        $0089               ; load bits value
                anda        #$07                ; mask X0089 bits 2:0
                bne         .LE2FE              ; branch ahead if any are set
                
                ldx         #$0090              ; load index with address of X0090
                jsr         LF1AD               ; this subroutine uses the index

.LE2FE          ldab        $205B               ; load bits value
                tst         $0088               ; test bank indicator bit
                bpl         .LE30A              ; branch if 0 (right bank)
                
                andb        #$FD                ; Left: clear X205B.1
                bra         .LE30C              ; branch

.LE30A          andb        #$FE                ; Right: clear X205B.0

.LE30C          stab        $205B               ; store bits value
                tst         $0086               ; test X0086.7
                bpl         .LE31F              ; branch ahead if X0086.7 is zero
                
                ldab        $008B               ; load bits value
                andb        #$01                ; mask X008B.0 (road speed > 4 KPH)
                bne         .LE31F              ; branch ahead if road speed > 4 KPH
                
                ldab        $C7D5               ; data value is probably $20 or $40
                bra         .LE322              ; branch

.LE31F          ldab        $C096               ; data value is $40

.LE322          tst         $0088               ; test bank indicator bit
                bpl         .LE32B              ; branch ahead if 0 (right bank)
                
                addb        $0093               ; Left: add contents of X0093 to B
                bra         .LE32D              ; branch

.LE32B          addb        $0092               ; Right:  add contents of X0092 to B

.LE32D          stab        $00CA               ; store B in X00CA (temporary location)
                ldd         $00C8               ; short term lambda trim (right or left)
                subb        $00CA               ; subtract B from upper byte of 16-bit value
                sbca        #$00                ; subtract with carry (A - M - C -> A)
                bcs         .LE33D              ; branch if carry/borrow is set
                
                subb        $00CA               ; subtract B from upper byte of 16-bit value
                sbca        #$00                ; subtract with carry (A - M - C -> A)

.LE33B          bcc         .LE3B0              ; if carry/borrow clear, branch to jump to LE50A (to set O2 fault)

.LE33D          ldaa        $0089               ; load bits value
                bita        #$04                ; test X0089.2
                bne         .LE3A6              ; if set, branch down to set short-term lambda trim to $0000
                
                ldaa        coolantTempCount    ; load ECT sensor count
                cmpa        $C17E               ; inside coolant temp table (value is $23 or 87 deg C)
                bcc         .LE3A6              ; if cooler, branch down to set short-term lambda trim to $0000

                ldaa        $00DC               ; load bits value
                bita        #$01                ; test X00DC.0 (set to 1 when road speed > 4 AND TPS < 40%)
                bne         .LE3A6              ; if set, branch down to set short-term lambda trim to $0000
                
;---------------------------------------------------------------------
; This code executed only when Road Speed > 4 AND TPS < 40%
;
; X00D4 (right) or X00D5 (left) can be incremented and when rollover
; occurs, the corresponding nibble in X00D6 is incremented.
;---------------------------------------------------------------------
                ldd         purgeValveTimer     ; load purve valve timer value
                beq         .LE359              ; skip subroutine if value is zero
                jsr         purgeValveBits      ; purge valve timer subroutine, sets or clrs carry before return
                bcs         .LE3A6              ; if carry set, branch down to set short-term lambda trim to $0000

.LE359          ldaa        $00D2               ; load bits value
                tst         $0088               ; test bank indicator bit
                bmi         .LE384              ; branch ahead if 1 (left bank)
                
;--------------
; Right Bank
;--------------
                oraa        #$01                ; set X00D2.0
                staa        $00D2               ; store it
                ldab        $00D4               ; load right bank counter
                incb                            ; increment X00D4 counter
                bne         .LE374              ; branch ahead if counter not zero
                
                ldab        $00D6               ; load dual nibble counter
                addb        #$01                ; add 1 to lower nibble
                bitb        #$02                ; test bit 2
                bne         .LE378              ; branch ahead if bit 2 is set
                
                stab        $00D6               ; store nibble counter
                clrb                            ; reset X00D4 counter to zero

.LE374          stab        $00D4               ; store byte counter
                bra         .LE3A6              ; branch down to set short-term lambda trim to $0000

.LE378          bita        #$10                ; test X00D2.4
                beq         .LE3AB              ; if zero, branch forward to set O2 fault bit
                
                ldaa        $00D3               ; load bits value
                oraa        #$10                ; set X00D3.4 (right bank fault bit)
                staa        $00D3               ; store it
                bra         .LE3A6              ; branch down to set short-term lambda trim to $0000

;--------------
; Left Bank
;--------------
.LE384          oraa        #$02                ; set X00D2.1
                staa        $00D2               ; store it
                ldab        $00D5               ; load left bank counter
                incb                            ; increment X00D5 counter
                bne         .LE398              ; branch ahead if counter not zero
                
                ldab        $00D6               ; load dual nibble counter
                addb        #$10                ; add 1 to upper nibble
                bitb        #$40                ; test bit 6
                bne         .LE39C              ; branch ahead if bit 6 is set
                
                stab        $00D6               ; store nibble counter
                clrb                            ; reset X00D5 counter to zero

.LE398          stab        $00D5               ; store byte counter
                bra         .LE3A6              ; branch down to set short-term lambda trim to $0000

.LE39C          bita        #$20                ; test X00D2.5
                beq         .LE3AB              ; if zero, branch forward to set O2 fault bit
                
                ldaa        $00D3               ; load bits value
                oraa        #$20                ; set X00D3.5 (left bank fault bit)
                staa        $00D3               ; store it
;-----------------------------------------
.LE3A6          clra                            ; clear A
                tab                             ; AB= $0000 (value will be written to short term trim location)
                jmp         .LE543              ; jump down to write short term trim
;-----------------------------------------

.LE3AB          jsr         LF3A3               ; <-- Set O2 Sensor Fault Bit (A or B, depending on bank bit)
                bra         .LE3A6              ; branch up to set short-term lambda trim to $0000
;-----------------------------------------

.LE3B0          jmp         .LE50A              ; jump ahead to next section after lean code

;------------------------------------------------------------------------------
; Lean Condition (Excess Oxygen, Low Voltage)
;------------------------------------------------------------------------------
.LE3B3          ldaa        $00D2               ; X00D2 holds bank related bits
                tst         $0088               ; test bank indicator bit
                bmi         .LE3C4              ; branch ahead if 1 (left bank)
                
                bita        #$01                ; Right: test X00D2.0
                beq         .LE3CE              ;       branch if bit is zero
                
                oraa        #$10                ;       set X00D2.4
                anda        #$FE                ;       clear X00D2.0
                bra         .LE3CC              ;       branch

.LE3C4          bita        #$02                ; Left: test X00D2.1
                beq         .LE3CE              ;        branch if bit is zero
                
                oraa        #$20                ;        set X00D2.5
                anda        #$FD                ;        clear X00D2.1

.LE3CC          staa        $00D2               ; store X00D2

.LE3CE          ldaa        $0089               ; load bits value
                bita        #$40                ; test X0089.6
                beq         .LE3F1              ; branch ahead if zero
                
                anda        #$BF                ; clear X0089.6
                staa        $0089               ; store it
                anda        #$07                ; mask X0089 bits 2:0
                bne         .LE3DF              ; branch ahead if any are set
                
                jsr         LF1D4               ; this subroutine uses MAF readings

.LE3DF          jsr         LF416               ; this subroutine manipulates bits in X00E2
                ldaa        $C097               ; data value is $04
                staa        $00BD               ; store in X00BD (working value for either X00BE or X00BF)
                ldaa        $0089               ; load bits value
                anda        #$01                ; mask X0089.0                
                beq         .LE3F4              ; branch ahead if bit is zero
                
                ldd         $008E               ; load X008E/8F (rich condition uses 0x0090/91)
                bra         .LE3F5              ; branch
                
;---------------------------------------
.LE3F1          jmp         .LE459              ; jump ahead in lean condition code
;---------------------------------------

.LE3F4          tab                             ; transfer A to B

.LE3F5          psha                            ; push A to stack
                ldaa        $205B               ; load bits value
                tst         $0088               ; test bank indicator bit
                bpl         .LE409              ; branch ahead if 0 (right bank)
                
                bita        #$02                ; Left: test X205B.1
                beq         .LE41E              ;        branch if bit is zero
                
                anda        #$FD                ;        clr X205B.1
                staa        $205B               ;        store it
                bra         .LE412              ;        branch

.LE409          bita        #$01                ; Right:  test X205B.0
                beq         .LE41E              ;        branch if bit is zero
                
                anda        #$FE                ;        clear X205B.0
                staa        $205B               ;        store it

.LE412          clr         $00CE               ; clear X00CE
                ldaa        $0069               ; load X0069 (rich cond uses data value XC096)
                staa        $00CF               ; store A in temporary location to be used later
                pula                            ; pull A from stack
                addd        $00CE               ; add double value X00CE/CF
                bra         .LE436              ; branch

.LE41E          pula                            ; pull A from stack
                tst         $0086               ; test X0086.7
                bpl         .LE431              ; branch ahead if X0086.7 is zero
                
                psha                            ; push A to stack
                ldaa        $008B               ; load bits value
                anda        #$01                ; mask X008B.0 (road speed > 4 KPH)
                pula                            ; pull A from stack
                bne         .LE431              ; branch if road speed > 4 KPH
                
                ldx         #$C7D1              ; rich code above uses #$C7D3 (both are 4000 decimal)
                bra         .LE434              ; branch

.LE431          ldx         #$C092              ; rich code above uses #$C094 (both are 8000 decimal)

.LE434          addd        $00,x               ; add 8000

.LE436          std         $00CE               ; store in X00CECF for later

                ldd         mafDirectHi         ; load MAF high
                addd        mafDirectLo         ; add MAF low
                lsrd                            ; shift right 1 bit
                lsrd                            ; shift right 1 bit
                lsrd                            ; shift right 1 bit (now upper 8 of 10 bits are in B)
                tba                             ; transfer B to A
                ldab        #$08                ; load B with 8 (number of columns in data table)
                ldx         #$C1CA              ; this points to air flow related data table
                jsr         indexIntoTable      ; index into table using MAF value (A is preserved)
                suba        $00,x               ; subtract indexed 1st row value from air flow sum (A)
                ldab        $10,x               ; load indexed 3rd row value
                mul                             ; and multiply 3rd row value and remainder
                asld
                asld                            ; 2 left shifts multiply by 4
                adda        $08,x               ; add the indexed 2nd row value
                staa        $0069               ; store MSB in X0069 (value can be reset elsewhere)
                ldd         $00C8               ; short term trim value (16-bit value)
                addd        $00CE               ; add 16-bit value
                bra         .LE495              ; branch

;---------------------------------------
;
;---------------------------------------
.LE459          jsr         LF224               ; this subroutine decrements value in X00BD if not zero
                ldaa        $0089               ; load bits value
                anda        #$07                ; mask X0089 bits 2:0
                bne         .LE468              ; branch ahead if any bits are set
                
                ldx         #$008E              ; load index with address X008E
                jsr         LF1AD               ; this subroutine uses the indexed value

.LE468          ldab        $205B               ; load bits value
                tst         $0088               ; test bank indicator bit
                bpl         .LE474              ; branch ahead if 0 (right bank)
                
                andb        #$FD                ; Left: clear X205B.1
                bra         .LE476              ;        branch

.LE474          andb        #$FE                ; Right:  clear X205B.0

.LE476          stab        $205B               ; store bits value
                tst         $0086               ; test X0086.7
                bpl         .LE489              ; branch ahead if X0086.7 is zero
                
                ldaa        $008B               ; load bits value
                anda        #$01                ; isolate X008B.0 (road speed > 4 KPH)
                bne         .LE489              ; branch ahead if road speed is > 4 KPH
                
                ldaa        $C7D6               ; data value cam be $1B or $36
                staa        $0069               ; reset X0069 to this value

.LE489          ldd         $00C8               ; short term trim value from X00C8/C9
                addb        $0069               ; add X0069 to low byte
                adca        #$00                ; if carry, add it to upper byte
                bcs         .LE497              ; and branch if the carry was set
                
                addb        $0069               ; else, add it again
                adca        #$00                ; and add carry again

.LE495          bcc         .LE50A              ; branch if carry is clear

.LE497          ldaa        $0089               ; load bits value
                bita        #$04                ; test X0089.2
                bne         .LE500              ; if set, branch ahead to set short term trim to $FFFF
                
                ldaa        coolantTempCount    ; load ECT sensor counts
                cmpa        $C17E               ; inside coolant temp table (value is $23 or 87 deg C)
                bcc         .LE500              ; if cooler, branch ahead to set short term trim to $FFFF
                
                ldaa        $00DC               ; load bits value
                bita        #$01                ; test X00DC.0 (road speed > 4 AND TPS < 40%)
                bne         .LE500              ; if set, branch ahead to set short term trim to $FFFF
                
                ldd         purgeValveTimer     ; load purge valve timer value (16 bits)
                beq         .LE4B3              ; branch ahead if zero
                
                jsr         purgeValveBits      ; purge valve timer subroutine, sets or clrs carry before return
                bcs         .LE500              ; if carry set, branch ahead to set short term trim to $FFFF

.LE4B3          ldaa        $00D2               ; load bits value
                tst         $0088               ; test bank indicator bit
                bmi         .LE4DE              ; branch ahead if 1 (left bank)
                
;--------------
; Right Bank
;--------------
                oraa        #$04                ; set X00D2.2
                staa        $00D2               ; store value
                ldab        $00D4               ; load counter
                incb                            ; increment X00D4 counter
                bne         .LE4CE              ; branch ahead if counter not zero
                
                ldab        $00D6               ; load dual nibble counter
                addb        #$01                ; add 1 to X00D6 low nibble
                bitb        #$04                ; test bit 2
                bne         .LE4D2              ; branch ahead if bit is set
                
                stab        $00D6               ; store dual nibble counter
                clrb                            ; reset X00D4 counter to zero

.LE4CE          stab        $00D4               ; store X00D4 counter
                bra         .LE500              ; branch ahead to set short term trim to $FFFF

.LE4D2          bita        #$40                ; test X00D2.6
                beq         .LE505              ; if zero, branch forward to set O2 fault bit
                
                ldaa        $00D3               ; load bits value
                oraa        #$04                ; set X00D3.2
                staa        $00D3               ; store bits value
                bra         .LE500              ; branch ahead to set short term trim to $FFFF
                
;--------------
; Left Bank
;--------------
.LE4DE          oraa        #$08                ; set X00D2.3
                staa        $00D2               ; store bits value
                ldab        $00D5               ; load counter
                incb                            ; increment X00D5 counter
                bne         .LE4F2              ; branch ahead if counter not zero
                
                ldab        $00D6               ; load dual nibble counter
                addb        #$10                ; add 1 to upper nibble
                bitb        #$20                ; test bit 5
                bne         .LE4F6              ; branch ahead if bit 5 is set
                
                stab        $00D6               ; store dual nibble counter
                clrb                            ; clear X00D5 counter

.LE4F2          stab        $00D5               ; store X00D5 counter
                bra         .LE500              ; branch ahead to set short term trim to $FFFF

.LE4F6          bita        #$80                ; test X00D2.7
                beq         .LE505              ; if zero, branch ahead to set O2 fault bit
                
                ldaa        $00D3               ; load bits value
                oraa        #$08                ; set X00D3.3
                staa        $00D3               ; store bits value

;------------------------------------------
                                                ; Common code: set short term trim to $FFFF
.LE500          ldd         #$FFFF              ; AB = $FFFF (this value will be written to the short-term trim location)
                bra         .LE543              ; branch down to common condition code
;------------------------------------------

.LE505          jsr         LF3A3               ; Set O2 Sensor Fault Bit (A or B, depending on bank bit)
                bra         .LE500              ; branch up to set short term trim to $FFFF
                
;---------------------------------------------------------------------
;                       Reset Counters
;---------------------------------------------------------------------
.LE50A          psha                            ; push A to stack
                ldaa        $00D6               ; load dual nibble counter
                tst         $0088               ; test bank indicator bit
                bmi         .LE519              ; branch ahead if set (left bank)
                
                clr         $00D4               ; Right: clear byte counter
                anda        #$F0                ;       clear lower nibble of dual nibble counter
                bra         .LE51E              ;       branch

.LE519          clr         $00D5               ; Left: clear byte counter
                anda        #$0F                ;        clear upper nibble of dual nibble counter

.LE51E          staa        $00D6               ; store dual counter with cleared nibble
                pula                            ; pull A from stack
                bra         .LE543              ; branch

;-------------------------------------------------------------------------------
;                     Open Loop Map Destination
;
; Fuel maps 1, 2 and 3 jump here immediately after the HO2 ADC measurement.
; Closed loop maps also jump here when conditions require open loop.
; Closed loop maps, running in closed loop, eventually get here too.
;
;------------------------------------------------------------------------------
.LE523          ldaa        $0089               ; load bits value
                anda        #$07                ; mask X0089 bits 2:0
                bne         .LE53B              ; branch ahead if any are set
                
                jsr         LF3C0               ; this routine clears some variables
                ldaa        $00D2               ; load bits value (bank related bits)
                tst         $0088               ; test bank indicator bit
                bmi         .LE537              ; branch ahead if 1 (left bank)
                
                anda        #$AA                ; Right: clear X00D2 bits 6,4,2,0
                bra         .LE539              ; branch

.LE537          anda        #$55                ; Left: clear X00D2 bits 7,5,3,1

.LE539          staa        $00D2               ; store X00D2

.LE53B          ldaa        #$FF                ; load A with $FF
                staa        $203C               ; reset fault code delay counter to $FF
                ldd         #$8000              ; load the default (neutral) value for short term trim
                
;------------------------------------------------------------------------------
;                  Final Stage of Short Term Trim Code
;
; Write short-term trim value for current bank back to the storage location.
; Write X00BD (working value) back to X00BE or X00BF
;
;------------------------------------------------------------------------------
.LE543          std         $00C8               ; store 16-bit short term trim value
                ldd         $00C8               ; (this is unneeded)
                tst         $0088               ; test bank indicator bit
                bpl         .LE564              ; branch ahead if 0 (right bank)
;--------------
; Left Bank
;--------------
                std         shortLambdaTrimL    ; store value as left short term trim
                ldab        $0089               ; load bits value
                bitb        #$40                ; test X0089.6
                beq         .LE558              ; branch if bit is zero
                
                orab        #$20                ; set X0089.5
                bra         .LE55A              ; branch

.LE558          andb        #$DF                ; clear X0089.5

.LE55A          andb        #$BF                ; clear X0089.6
                stab        $0089               ; store bits value
                ldab        $00BD               ; load working value
                stab        $00BF               ; store it in X00BF
                bra         .LE57A              ; branch
;--------------
; Right Bank
;--------------
.LE564          std         shortLambdaTrimR    ; store value as left short term trim
                ldab        $0089               ; load bits value
                bitb        #$40                ; test X0089.6
                beq         .LE570              ; branch if bit is zero
                
                orab        #$10                ; set X0089.4
                bra         .LE572              ; branch

.LE570          andb        #$EF                ; clear X0089.4

.LE572          andb        #$BF                ; clear X0089.6
                stab        $0089               ; store bits value
                ldab        $00BD               ; load working value
                stab        $00BE               ; store it in X00BE

IF BUILD_R3365
;-----------------------------------------------------------
; Defender Only (R3365)
;-----------------------------------------------------------

.LE57A	   	    ldaa	    #$27                ; 
	   	        staa	    AdcControlReg1
	   	        ldaa	    #$C8
	   	        staa	    AdcDataLow
	   	        jsr	        LFA46
ELSE

.LE57A          jsr         rdSpdCompTest       ; road speed comparator test

ENDC

;---------------------------------------------------------------------------------------------------
;                                     Purge Valve Stuff
;---------------------------------------------------------------------------------------------------
                ldaa        fuelMapNumber       ; load fuel map number
                beq         .LE5A5              ; branch ahead if fuel map is zero
                cmpa        #$04                ; compare fuel map number with 4
                bcc         .LE5A5              ; branch ahead if fuel map is 4 or 5
                
;----------------------------------
; Fuel map 1, 2 and 3 (open loop)
;----------------------------------
                ldab        $008D               ; load bits value
                bitb        #$10                ; test X008D.4
                beq         .LE5EA              ; branch ahead if X008D.4 is zero
                
                ldd         engineRPM           ; load engine RPM (16-bit value)
                subd        $202D               ; previously stored eng RPM value (in purge valve subroutine)
                bcs         .LE5EA              ; branch ahead if current RPM < X202D value (neg value)
                
                subd        #$001E              ; positive result, subtract an additional 30 decimal
                bcs         .LE5EA              ; branch ahead if result is now negative
                
                ldab        $008D               ; load bits value
                andb        #$6F                ; clear X008D.7 and X008D.4
                stab        $008D               ; store bits value
                ldd         $C145               ; data value is 12,000 decimal
                std         $0098               ; reset down counter to 12000 dec
                bra         .LE5EA              ; branch ahead to fault code tests
                
;----------------------------------
; Fuel map 0, 4 and 5 (closed loop)
;----------------------------------
.LE5A5          ldab        $008D               ; load bits value
                bitb        #$10                ; test X008D.4
                beq         .LE5EA              ; branch ahead if X008D.4 is zero
                
                ldaa        shortLambdaTrimR    ; load right short term trim (MSB only)
                cmpa        $C1F1               ; data value is $56
                bcs         .LE5BD              ; branch ahead if right trim MSB < $56
                
                ldaa        secondaryLambdaR    ; load MSB of other right Lambda value
                adda        $C144               ; data value is $0A (add 10 decimal)
                bcs         .LE5CC              ; branch ahead if rollover
                
                cmpa        $009A               ; compare value with X009A
                bcc         .LE5DC              ; branch ahead if value > X009A

.LE5BD          andb        #$6F                ; clear X008D.7 and X008D.4
                stab        $008D               ; store bits value
                ldd         $C145               ; data value is 12,000 decimal
                std         $0098               ; reset down counter to 12000 dec
                
                ldaa        $0088               ; load bits value
                anda        #$9F                ; clear X0088 bits 6:5
                staa        $0088               ; store bits value

.LE5CC          ldaa        $00DD               ; load bits value
                anda        #$F7                ; clear X00DD.3
                staa        $00DD               ; store bits value
                ldaa        $203B               ; load bits value
                oraa        #$01                ; set X203B.0
                staa        $203B               ; store bits value
                bra         .LE5EA              ; branch ahead to next section

.LE5DC          ldaa        secondaryLambdaR    ; load MSB of other right Lambda value
                suba        $009A               ; subtract X009A
                adda        $C1EC               ; data value is $01 or $02 (add this value)
                cmpa        $C1ED               ; data value is $02 or $04 (compare with this value)
                bhi         .LE5CC              ; branch up if value is higher than XC1ED
                bra         .LE5EA              ; (unneeded)

;---------------------------------------------------------------------------------------------------
;						Test for Fault Codes 34, 36 and 59
;
; This section is skipped when eng RPM > 4185.
;
; Fault Code 34 = Injector Bank A
; Fault Code 36 = Injector Bank B
; Fault Code 59 = Air Leak or Low Fuel Pressure (This fault is unused and masked out.)
;    
; The short term trim values appear negative as they increase fueling due to the $8000 based
; offset of the values (msb is set). If the high byte of the trim value is over $E0 ($F0 for
; example) it indicates that much more fuel being called for. This can be the result of an air
; leak, low fuel pressure or a problem with the injector bank.
;
;---------------------------------------------------------------------------------------------------
.LE5EA          ldaa        ignPeriod           ; load ignition period MSB
                cmpa        #$07                ; is period at least $0700 (LT 4185 RPM)
                bcc         .LE5F3              ; branch to avoid jump for normal engine speed
                jmp         .LE72B              ; <-- high engine speed, jump way down skip fault tests
                
;---------------------------------------------
                                                ; <-- engine speed is below 4185 RPM
.LE5F3          ldaa        $008C               ; load bits value
                bita        #$02                ; test X008C.1 (double pulse timeout bit)
                beq         .LE667              ; if zero, branch to next fault check
                
                anda        #$30                ; mask X008C bits 5:4 (unused bits)
                cmpa        #$30                ; test X008C.5 and X008C.4
                bne         .LE667              ; branch ahead if either bit is set
                
                ldab        faultBits_4A        ; load fault bits from X004A
                ldaa        $00D3               ; load bits value
                anda        #$0C                ; mask X00D3 bits 3:2
                beq         .LE667              ; branch ahead if both bits are zero
                
                ldaa        $00DC               ; load bits value
                bita        #$20                ; test X00DC.5
                bne         .LE62F              ; branch ahead if bit is set
                
                oraa        #$20                ; set 00DC.5
                staa        $00DC               ; store bits value
                ldaa        shortLambdaTrimR    ; load MSB of right short term trim (128 +/-)
                cmpa        $C1F3               ; data value is $E0
                bcs         .LE62B              ; skip to injector fault test if < E0
                
                ldaa        shortLambdaTrimL    ; load MSB of left short term trim (128 +/-)
                cmpa        $C1F3               ; data value is $E0
                bcs         .LE627              ; skip to injector fault test if < $E0
                
                ldaa        faultBits_4D        ; if here, both banks seem to need much more fuel than normal
                oraa        #$10                ; <-- Set Fault Code 59 (Unused Group Fault, air leak or low fuel pressure)
                staa        faultBits_4D
                bra         .LE62D

.LE627          orab        #$01                ; <-- Set Fault Code 34 (Injector Bank A Fault) LEFT SIDE!!
                bra         .LE62D

.LE62B          orab        #$04                ; <-- Set Fault Code 36 (Injector Bank B Fault) RIGHT SIDE!!

.LE62D          stab        faultBits_4A

;--------------------------------------------------------------------------------
; The Group Fault bit is masked out and cannot set the MIL. If set, however,
; it does enable this code section to execute. Here, software tries to determine
; if the problem is an air leak or low fuel pressure. Interestingly, these two
; faults are also masked out and unused.
;
; Fault Code 23 - Low fuel Pressure
; Fault Code 28 - Air Leak
;--------------------------------------------------------------------------------
.LE62F          ldaa        faultBits_4D        ; load fault bits value (X004D)
                bita        #$10                ; test X004D.4 (Fault Code 59)
                beq         .LE667              ; If not set, skip ahead
                
                ldab        faultBits_4C        ; load fault bits X004C
                ldaa        fuelMapLoadIdx      ; load fuel map row index
                cmpa        #$30                ; compare with $30
                bcs         .LE667              ; if row index < $30, skip ahead
                
                ldaa        shortLambdaTrimR    ; load MSB of right short term trim (128 +/-)
                cmpa        #$FF                ; check for maxed out value
                bne         .LE65A              ; if max, skip down
                
                ldaa        shortLambdaTrimL    ; load MSB of left short term trim (128 +/-)
                cmpa        #$FF                ; check for maxed out value
                bne         .LE65A              ; if max, skip down

                ldaa        $00DF               ; load fault delay counter
                inca                            ; increment it
                cmpa        #$32                ; compare it with 50 decimal
                beq         .LE654              ; branch to set fault code 23
                
                staa        $00DF               ; store counter                
                bra         .LE667              ; branch to next section
                
                                                ; code gets here when X00DF counter gets to 50 decimal
.LE654          orab        #$01                ; <-- set fault code 23 (low fuel pressure -- unused)
                stab        faultBits_4C
                bra         .LE667              ; branch to next section

.LE65A          clr         $00DF               ; clear delay counter
                bitb        #$01                ; test for Fault Code 23
                bne         .LE667              ; if set, don't set Fault Code 28
                
                ldaa        faultBits_4B
                oraa        #$08                ; <-- set fault code 28 (air leak -- unused)
                staa        faultBits_4B

;---------------------------------------------------------------------------------------------------
;                             Injector Bank Fault Check
;
; Bits X00D3.4 and X00D3.5 can be set above when the O2 volatge is high (rich, depleted oxygen)
;
;---------------------------------------------------------------------------------------------------
.LE667          ldab        faultBits_4A        ; load fault bits value X004A
                ldaa        $00D3               ; load bank fault bits
                anda        #$30                ; test 2 bank related fault bits X00D3.5 and X00D3.4
                beq         .LE697              ; branch to next section if both are clear
                
                ldaa        $00DC               ; load bits value
                bita        #$10                ; test X00DC.4
                bne         .LE697              ; if zero, branch to next section
                
                oraa        #$10                ; set X00DC.4 (may indicate that injector fault is already set)
                staa        $00DC
                ldaa        shortLambdaTrimR    ; load MSB of right short term trim (128 +/-)
                cmpa        $C1F2               ; data value is $30
                bcc         .LE693              ; if trim > $30, branch to set Inj B Fault
                
                ldaa        shortLambdaTrimL    ; load MSB of left short term trim (128 +/-)
                cmpa        $C1F2               ; data value is $30
                bcc         .LE68F              ; if trim > $30, branch to set Inj A Fault
                
                ldaa        faultBits_4C
                oraa        #$01                ; set unused fuel pressure fault (Code 23)
                staa        faultBits_4C
                bra         .LE695              ; branch

.LE68F          orab        #$01                ; set injector bank A fault (Code 34)
                bra         .LE695              ; branch to store X004A

.LE693          orab        #$04                ; set injector bank B fault (Code 36)

.LE695          stab        faultBits_4A        ; store X004A fault bits value

;------------------------------------------------------------------------------
;
; This section is skipped for open loop fuel maps. It manipulates the lambda trim
; values (normally in 0040 thru 0047) using the right or left short term trim values
;
;   X0040/41    A value similar to short term trim
;   X0042/43	Long term trim (Right)
;   X0044/45	A value similar to short term trim    
;   X0046/47    Long term trim (Left)
;------------------------------------------------------------------------------
.LE697          ldaa        $0089               ; load bits value
                anda        #$03                ; mask X0089.1 and X0089.0
                bne         .LE71A              ; if either set, branch and skip long term trim adjust
                
                ldaa        fuelMapNumber       ; load fuel map number
                beq         .LE6A6              ; if zero, branch to continue
                
                cmpa        #$04                ; compare map number with 4
                bcs         .LE71A              ; continue if 4 or 5, else skip long term trim adjust

.LE6A6          ldaa        $00CE               ; load value from rich or lean code above
                oraa        $00CF               ;  OR  value from rich or lean code above
                beq         .LE71A              ; if zero, branch and skip long term trim adjust
                
                ldaa        coolantTempCount    ; load ECT sensor count
                cmpa        $C17E               ; inside coolant temp table (value is $23 or 87 deg C))
                bcc         .LE71A              ; if cooler than 87C, branch to skip long term adjustment

                ldaa        $0088               ; test bank indicator bit
                bmi         .LE6BE              ; branch if bit is 1 (left bank)
                
                ldd         shortLambdaTrimR    ; Right:  load right short term trim into AB regs
                ldx         #secondaryLambdaR   ;         load other right Lambda value into index reg
                bra         .LE6C3              ; branch

.LE6BE          ldd         shortLambdaTrimL    ; Left: load left short term trim into AB regs
                ldx         #secondaryLambdaL   ;        load other left Lambda value into index reg

;-------------------------------------------------------------------------
; This block uses the short term trim values to adjust the values in
; X0040/41 and X0044/45 (these are not the long term trim values)
;
; If Right,  AB = right  short trim value,  X = #Left
; If Left, AB = left short trim value,  X = #secondaryLambdaLeft
;-------------------------------------------------------------------------
.LE6C3          jsr         LF119               ; subroutine reduces AB to 1/2 or 1/4
                pshb                            ; push B to stack
                psha                            ; push A to stack
                ldd         $00,x               ; load the other Lambda value
                jsr         LF119               ; subroutine reduces AB to 1/2 or 1/4
                subd        $00,x               ; subtract original value
                jsr         absoluteValAB       ; get the absolute value
                std         $00,x               ; store it as the other value
                pula                            ; pull MSB of short term trim
                pulb                            ; pull LSB of short term trim
                addd        $00,x               ; add indexed value
                std         $00,x               ; and store as new "other" value
                
;---------------------------------------------------------------------------------------------------
;
;                                Long Term Trim Adjustment
;                                    
;---------------------------------------------------------------------------------------------------
                ldab        $008D               ; load bits value
                bitb        #$11                ; test X008D.4 and X008D.0
                bne         .LE72B              ; if either bit is set, branch to next section
                
                ldab        $00DC               ; load bits value
                bitb        #$08                ; test X00DC.3
                beq         .LE72B              ; if X00DC.3 is zero, branch to next section
                
                ldab        $0088               ; test bank indicator bit
                bmi         .LE6F0              ; if bit is 1, branch ahead to left bank
                
                bitb        #$40                ; Right: test X0088.6
                bne         .LE72B              ;       if set, branch to next section
                bra         .LE6F4              ;       branch

.LE6F0          bitb        #$20                ; Left: test X0088.5
                bne         .LE72B              ;        if set, branch to next section

.LE6F4          ldaa        $0086               ; load bits value
                bpl         .LE71A              ; if X0086.7 is zero, branch ahead to next section
                
                ldaa        $008B               ; load bits value
                anda        #$01                ; mask X008B.0 (road speed > 4 KPH)
                bne         .LE72B              ; if road speed > 4, branch to next section
                
                ldd         $00,x               ; X is the "other" Lambda value
                subd        #$8000              ; subtract $8000 
                bcc         .LE71C              ; branch if still positive

;----------------------------------------------------------------
; AB is Lambda value (X0040/41 or X0044/45) minus $8000 (and is negative)
; X  is address of X0040 or X0044
;----------------------------------------------------------------
                jsr         LF171               ; can subtract 1500 from short term trim location (preserves AB)
                jsr         absoluteValAB       ; convert to absolute value
                jsr         LF0FC               ; reduces value to 1/2 or 1/4 (uses code control value)
                subd        $02,x               ; subtract long term trim, X0042/43 (right) or X0046/47 (left)
                bcs         .LE715              ; branch if no underflow
                
                ldd         #$0000              ; clip it at zero

.LE715          jsr         absoluteValAB
                std         $02,x               ; store long term trim

.LE71A          bra         .LE72B              ; this branch is also used above
;----------------------------------------------------------------
; AB is Lambda value (X0040/41 or X0044/45) minus $8000 (and is negative)
; X  is address of X0040 or X0044
;----------------------------------------------------------------

.LE71C          jsr         LF171               ; can subtract 1500 from short term trim location (preserves AB)
                jsr         LF0FC               ; reduces value to 1/2 or 1/4 (uses code control value)
                addd        $02,x               ; add long term trim, X0042/43 (right) or X0046/47 (left)
                bcc         .LE729              ; branch if no overflow
                
                ldd         #$FFFF              ; clip it at $FFFF

.LE729          std         $02,x               ; store long term trim


IF BUILD_R3365
;-----------------------------------------------------------
; Defender Only (R3365)
;-----------------------------------------------------------

.LE72B	   	    ldaa	    #$27                ; 
	   	        staa	    AdcControlReg1
	   	        ldaa	    #$C8
	   	        staa	    AdcDataLow
	   	        jsr	        LFA46
ELSE

.LE72B          jsr         rdSpdCompTest       ; road speed test, loads X2012 in B before returning
	   	        
ENDC


;---------------------------------------------------------------------------------------------------
;	Code above jumps ahead to this point if engine speed is GT 4185 RPM in order to 
;	skip some code (above)
;
;	Normally we have one injector pulse per 4 coil pulses, but for startup the rate doubles for
;	a short period (about 3 secs). Also, the pulse width is wider.
;
;	It looks like the double injector pulses at startup are a result of X009D/9E not being zero.
;	This 16-bit value is init to 192 and counts down at a rate proportional to the ICI. During
;	normal start, this period is only equal to about 3 seconds. The X008C.0 toggle bit is used
;   to skip fueling every other time through.
;
;	During double pulse time: (may not be correct)
;	
;	008C.0		0088.7
;	(div/2)		(bank)
;	-------------------
;	  0			  0			Fuel Right
;	  1			  0			
;	  0			  1			Fuel Left
;	  1			  1			
;	  0			  0			Fuel Right
;	  1			  0			(and so on)
;
;	LEADB skips fueling and bank toggle	
;---------------------------------------------------------------------------------------------------
                ldaa        $008C               ; load bits value
                bita        #$02                ; test X008C.1 (double pulse timeout bit)
                bne         .LE73F              ; branch ahead if bit is zero (0 = not timed out)
                
                ldx         $009D               ; init to 192, decrements at spark rate
                beq         .LE74C              ; branch if zero
                
                dex                             ; decrement the 192 count double pulse startup delay
                stx         $009D               ; store it
                ldaa        $0085               ; test X0085.7 (indicates no or low eng RPM)
                bmi         .LE76F              ; branch if set (engine cranking?)

.LE73F          ldaa        $008C               ; if here, RPM OK (eng is running), load bits value

.LE741          eora        #$01                ; toggle X008C.0 (div by 2 bit)
                staa        $008C               ; store it
                bita        #$01                ; test X008C.0 (div by 2 bit)
                beq         .LE750              ; if zero, branch to continue
                
                jmp         .LEADB              ; Jump way down to Column Index and RPM calculation
                                                ; This skips the bank toggle!!

;---------------------------------------------
                                                ; code branches to here after X009D/9E reaches zero
.LE74C          oraa        #$02                ; set X008C.1 (to indicate double pulse time is over)
                bra         .LE741              ; branch
;---------------------------------------------
; code gets here only if MAF is being measured
                                                ; this code executes every other time while 192 count not zero(maybe not!!)
.LE750          ldaa        $0089               ; load bits value
                bmi         .LE76C              ; branch ahead if X0089.7 is set
                
                ldaa        $00C1               ; load X00C1
                inca                            ; increment it
                cmpa        $C13B               ; compare with data value 20 decimal
                bcc         .LE760              ; branch if X00C1 is greater than 20
                
                staa        $00C1               ; store X00C1
                bra         .LE766              ; branch

.LE760          ldab        $0087               ; branches here when X00C1 >= 20 dec
                andb        #$7F                ; clr X0087.7
                stab        $0087
                
;---------------------------------------------
;	Eng RPM limit test 
;---------------------------------------------
                                                ; branches here when X00C1 < 20 dec
.LE766          ldaa        $0086               ; load bits value
                bita        #$20                ; test X0086.5 (1 = RPM < limit, 0 = RPM > limit)
                bne         .LE76F              ; branch if RPM < limit

.LE76C          jmp         .LEAD5              ; RPM at limit, jump to tog bank bit & fall into RPM calc
;---------------------------------------------

                                                ; branches here from above if eng cranking or low RPM
.LE76F          tst         $0085               ; test X0085.7 (indicates no or low eng RPM)
                bpl         .LE7CC              ; branch if clear (engine running)
                
;---------------------------------------------------------------------------------------------------
;                            Fueling Selection for Engine Cranking
;
; This section of code is only executed until the engine starts, after that it's bypassed.
; 
; There are 3-row by 12-column data tables in the data section of the PROM. There is a default table
; located at XC0D0 plus 5 more fuel map specific tables within the fuel map data structures. The top
; row represents engine coolant temperature in ECT sensor counts. The 2nd row is the fueling value
; for that temperature bracket. The 3rd row is an extra, time based fueling component. When the ECU
; is turned on, two variables are initialized from this table. X009B is initialized from the 2nd row
; value and X009C is initialized from the 3rd row value.
;
; During cranking, the fuel pulse width is determined by the value in X009B. When the engine starts,
; the value in X009C increases the fuel. However, this value is reduced to zero at the rate of 1 Hz.
; 
; This is a typical table:
;
; C0D0 : 00 12 1B 25 47 75 94 B0 C8 E2 E8 EC    ; <-- ECT sensor count
; C0DC : 0B 0A 07 0D 1A 2A 3C 46 46 46 50 50    ; inits X009B (cranking fueling value above $EC)
; C0E8 : 1C 0D 06 0A 14 19 25 2B 2B 2B 2D 2D    ; inits X009C (time fueling component, 1 Hz countdown)
;
;
; There's one problem though. Ambient temperature can be colder than the temperature range of the
; table. The coldest value listed here is $EC which is about -18 C or zero F. This value, which is
; located at XC0DB is compared with current ECT and, if ECT is colder, a different strategy is used.
; A New Englander might call this strategy "wicked cold startup".
;
; Wicked cold startup involves 2 things. First, the injector pulse width is based solely on engine
; RPM. Second, the injector pulse is broken up into 11 smaller "micro-pulses", presumably to better
; atomize the fuel.
;
;---------------------------------------------------------------------------------------------------


;---------------------------------------------
; Engine is cranking so select fueling type
;---------------------------------------------
                ldaa        coolantTempCount    ; load ECT sensor counts
                cmpa        $C0DB               ; last table value, $E8 to $EC ($EC= -18 C or zero F)
                bcs         .LE7A4              ; branch ahead to normal startup if warmer than this
                
;------------------------------------------------------------------------------
;                           Wicked Cold Startup
;
; The code section below multiplies the MSB of the ignition period by a factor
; which varies depending on fuel map and tune numbers. This number becomes
; greater as RPM gets lower. There is a minimum value which is determined by
; the value 1500. The value 20 determines the number of micro-pulses. The
; formula is:  value_in_X00A6/2 + 1 = number_of_micropulses
;
; Normal engine cranking speed is between 100 and 200 RPM. This software
; considers the engine to be running when RPM exceeds 500 (375 for the cold
; weather chip). This table shows the relationship between RPM, MSB of the
; spark period, the muliplication result (using $0A) and the resultant injector
; pulse (as measured on an oscilloscope). The point at which the minimum value
; of 1500 takes effect is clear to see. 
;
;		  Ign.Per.	 Mpy by	    Pulse
;   RPM    (MSB)       $0A
; -------------------------------------------
;   134     DA	      2180	    3.3 mS
;   150     C3	      1950 	    3.1 mS
;   200     92	      1460	    2.6 mS	<-- this is the 1500 minimum
;   250     75	      1170	    2.6 mS
;   300     61	       970	    2.6 mS
;   350     53	       830      2.6 mS
;   400     49	       730      2.6 mS
;   450     41	       650      2.6 mS
;   480     3D	       610	    2.6 mS
;
; By the way, main voltage has a large affect on the injector pulse width. The 
; table above was measured with main voltage input set to 12.02 VDC. The table
; below shows the effect of varying the voltage for rhe 2.6 mSec pulse.
;
; ADC	Volts	Pulse
; ----	-----	-------
; 200	13.96	2.40 mS
; 186	12.96	2.50 mS
; 172	12.02	2.60 mS
; 158	11.03	2.85 mS
; 144	 9.99	3.10 mS
; 130	 9.01	3.40 mS
; 115	 8.01	3.70 mS
;
; One final point about the mechanics of how this works. This interrupt code
; fires the injector bank and returns to the main loop, so the main loop is
; being executed while the injector is open. There is a call to subroutine
; LF04D (coldStart.asm) in the main loop. If the value in X00A6 is zero, the
; subroutine just returns, however, if the value is non-zero, the state of
; the injector is toggled and the counter in X00A6 is decremented.
;
;------------------------------------------------------------------------------
                ldaa        #$14                ; (20 dec) controls number of micro-pulses
                staa        $00A6               ; store it
                ldaa        ignPeriodFiltered   ; load MSB of filtered ignition period
                ldab        fuelMapNumber       ; load fuel map number
                cmpb        #$02                ; compare with 2
                bcc         .LE78C              ; branch if fuel map is 2, 3, 4 or 5
                
.LE788          ldab        #coldStartupFactor  ; fuel maps 0, 1 and 5 use this value
                bra         .LE792              ; (value is $12 for cold weather chip)
                
.LE78C          cmpb        #$05                ; compare with 5
                beq         .LE788              ; branch up if fuel map 5
                
                ldab        #$07                ; fuel maps 2, 3 and 4 use this value

.LE792          mul                             ; mpy ign. period by value in B
                std         $00C8               ; store 16-bit result at X00C8/C9
                subd        #$05DC              ; subtract 1500
                bcc         .LE79F              ; branch ahead if value > 1500
                
                ldd         #$05DC              ; otherwise, clip value at 1500
                bra         .LE7A1

.LE79F          ldd         $00C8               ; load fueling value into AB

.LE7A1          jmp         .LE983              ; jump down to Phase II Compensation

;------------------------------------------------------------------------------
;                           Normal Cranking Fuel
;
; This section calculates the cranking fuel pulse within the normal temperature
; range, using the 2nd row value from the 3-row by 12 column data table. If the
; engine is warm and the throttle is depressed while cranking, the throttle
; position affects the amount of fuel.
;
;------------------------------------------------------------------------------

.LE7A4          ldaa        coolantTempCount    ; load ECT sensor count
                cmpa        #$40                ; compare with $40 (about 60 C or 140 F)
                bcc         .LE7C2              ; branch ahead cooler
                
                ldd         throttlePot         ; ECT > 60 C, load 16-bit TPS value
                subd        #$0070              ; subtract $70 from TP value
                bcs         .LE7C2              ; branch ahead if TP is LT $0070
                
                lsrd                            ; if here, warm engine and throttle depressed
                lsrd                            ; 2 X lsrd gets the top 8 bits into 1 byte
                ldaa        $C0F6               ; data value is $19 (25 dec)
                mul                             ; mpy 1/4 TPS by 25
                cmpa        $C0F7               ; compare result MSB with value $0A
                bcs         .LE7C5              ; branch ahead if result < $0A00
                
                ldaa        $C0F7               ; this limits result to $0Axx maximum
                clrb                            ; clrb, result now $0A00
                bra         .LE7C5              ; branch

.LE7C2          ldd         #$0000              ; if here, cooler than 60 C or no throttle

.LE7C5          addb        #$FF                ; add $FF to 16-bit value
                adca        $009B               ; add both the carry bit (if any) and the 2nd
                                                ; row table value to the final 16-bit value
                
                jmp         .LE983              ; jump down to Phase II Compensation
                
;------------------------------------------------------------------------------
;          Time, Bank Time, Coolant Temp & Fuel Temp Adjustment
;
; This is the start of the normal fueling process. When engine is running, code
; branches here from LE76F above. A 16-bit multiplier value is calculated here
; and stored in X00CA/CB for later use. This value is the result of 4 different
; input factors:
; 
; 1 - The reducing value from the 3rd row of the 3 x 12 data table. This is the
;     value that is stored in X009C at initial power-on. This value is reduced
;     to zero at a 1 Hz rate by a periodically called timer routine. When tha
;     value reaches zero bit X008A.6 is cleared.
;
; 2 - There are additional bank specific down counters that are stored in X2020
;     (right) and X2021 (left). These are both initialized from the data value
;     in XC1FF, so they cannot differ from each other. This value is usually $03.
;
; 3 - The value 'coolantTempAdjust' is an engine temperature based adjustment.
;     It typically starts in the high 40's (decimal) and reduces to the high
;     30's as the engine warms. It does not go to zero as one might expect.
;
; 4 - Finally, there may be a fuel temperature adjustment, which is applied
;     under unusual circumstances.
;
; The final 16-bit value is checked for rollover and limited, if necessary, to $FFFF.
;
;------------------------------------------------------------------------------
.LE7CC          clrb                            ; clear B
                ldaa        $008A               ; load bits value
                bita        #$40                ; test X008A.6 (0 = timeout of X009C 3rd row 1Hz value)
                beq         .LE7D5              ; branch to skip loading X009C if timeout has occurred
                
                ldab        $009C               ; value from 3rd row of startup fueling table
                
.LE7D5          tst         $0088               ; test bank indicator bit
                bmi         .LE7DF              ; branch if 1 (left bank)
                
                addb        $2020               ; X2020 is the right bank startup down-counter
                bra         .LE7E2              ; branch

.LE7DF          addb        $2021               ; X2021 is the left bank startup down-counter

.LE7E2          clra                            ; clear A
                addb        coolantTempAdjust   ; add ECT based fuel adjustment
                adca        #$00                ; if rollover, add the carry bit to A
                asld                            ; x2
                asld                            ; x4
                addd        #$0096              ; add this value
                asld                            ; x2
                asld                            ; x4
                asld                            ; x8
                asld                            ; x16
                asld                            ; x32
                psha                            ; push the upper byte
                ldaa        $008A               ; load bits value
                bita        #$02                ; test X008A.1 (may be EFT related, usually set)
                pula                            ; pull the upper byte
                bne         .LE800              ; branch if not zero (usually branches
                
                addd        $009F               ; this value related to fuel temperature
                bcc         .LE800              ; if value did not overflow, use it
                
                ldd         #$FFFF              ; else clip at $FFFF

.LE800          std         $00CA               ; store double value for future use

;------------------------------------------------------------------------------
;          Lambda and Throttle Rate Adjustment to Fueling Value
;
; The short term trim value is a 16-bit value having a neutral point of $8000.
; The value $FFFF represent maximum fuel addition and the number $0000
; represents maximum fuel reduction.
;
; The Throttle Direction & Rate value is a 16-bit value that has a neutral
; point of $0400 (1024 decimal). An opening throttle results in a higher
; number and a closing throttle results in a lower number.
;
;------------------------------------------------------------------------------
                ldd         $00C8               ; X00C8/C9 is still the short term trim value
                asld                            ; shift left double (shift msb into carry)
                staa        $00CC               ; store shifted MSB in X00CC
                bcc         .LE80F              ; branch if value is below 32K
;---------------------------------------
; Short term trim wants to increase fuel
;---------------------------------------
                tab                             ; transfer shifted MSB into B
                clra                            ; clear A
                addd        $005D               ; add throttle direction and rate (1024 +/-)
                bra         .LE818              ; branch
;---------------------------------------
; Short term trim wants to decrease fuel
;---------------------------------------
                                                ; stored short term trim < 32K
.LE80F          ldd         $005D               ; throttle direction and rate (1024 +/-)
                com         $00CC               ; 1's comp of short term trim MSB  
                subb        $00CC               ; subtratc from TPS D&R
                sbca        #$00                ; if underflow, subtract 1 from upper byte

.LE818          pshb                            ; push B to stack
                ldab        $008C               ; load bits value
                bitb        #$08                ; test X008C.3 (may indicate high throttle)
                pulb                            ; pull B (flags not affected)
                beq         .LE828              ; branch ahead if bit X008C.3 is zero
                
                addb        $006C               ; add throttle pot related value to low byte
                adca        #$00                ; handle rollover
                addb        $006C               ; add throttle pot related value to low byte
                adca        #$00                ; handle rollover

.LE828          addd        #$0080              ; add $0080 to 16-bit value
                asld
                asld
                asld
                asld                            ; four asld's is a div by 16
                jsr         mpy16               ; mpy AB by X00CA/CB
                std         $00CA               ; store updated result at X00CA/CB
                
;------------------------------------------------------------------------------
;              Reinitialize RAM with Fuel Map Specific Values
;
; It's not clear why this is done every time through the spark interrupt code.
; It might be for robustness, assuming RAM can be occasionally corrupted. Or it
; might be to defeat any attempts to "hack" or make run-time changes. Since
; the values are reloaded from PROM just before use, any overwiting through
; the serial port would be ineffective.
;
; The following variables are reinitialized:
;
;   X2008/09 - the 16-bit fuel map multiplier from offset $80 in the fuel map
;   X200A    - value used to calculate the load based fuel map row index
;   X200B    - the safety margin to be added to the RPM limit below
;   X200C/0D - the 16-bit engine RPM limit (in 2 uSec period format)
;   X200E    - an ECT sensor related value
;   X200F    - an ECT sensor related value
;   X2010    - (todo)
;   X2011    - multiplier for TPS D&R (closing throttle only)
;   X0078    - ADC control table pointer
;
; The last 8 bytes in the fuel map data structure represent 7 values (one is
; a 2-byte value) that are stored in RAM at addresses X200A through X2011.
;
;
;------------------------------------------------------------------------------
                ldx         #$C082              ; addr of default ADC control table
                stx         adcMuxTableStart    ; store as current table
                ldx         #limpHomeMap        ; load X with addr XC000
                ldaa        fuelMapNumber       ; load fuel map number
                beq         .LE868              ; skip this code if fuel map is zero
                
                ldx         fuelMapPtr          ; load the current fuel map pointer
                ldab        #mapMultiplierOffset ; load B with offset $80
                abx                             ; add offset to pointer
                ldd         $00,x               ; load the 16-bit fuel map multiplier
                std         $2008               ; store it
                ldd         $8A,x               ; index becomes $80 + $8A
                std         $200A               ; store fm row multiplier and RPM margin
                ldd         mapRpmLimitOffset,x ; offset is now $80 + $8C
                std         rpmLimitRAM         ; store 16-bit RPM limit
                ldd         $8E,x               ; offset is now $80 + $8E
                std         $200E               ; store two coolant temp related values
                ldd         $90,x               ; offset is now $80 + $90
                std         $2010               ; store last 2 values
                ldab        #mapAdcMuxTableOffset ; load B with offset $7A
                abx                             ; add to X ($80 + $7A = $FA)
                stx         adcMuxTableStart    ; store ADC table pointer
                ldx         fuelMapPtr          ; load X with base fuel map ptr (later use)


IF BUILD_R3365
;-----------------------------------------------------------
; Defender Only (R3365)
;-----------------------------------------------------------
.LE868	   	    ldaa	    #$27
	   	        staa	    AdcControlReg1
	   	        ldaa	    #$C8
	   	        staa	    AdcDataLow
	   	        jsr	        LFA46
ELSE

.LE868          jsr         rdSpdCompTest       ; road speed test, loads X2012 in B before returning
	   	        
ENDC

                ldaa        $0087               ; load bits value
                bita        #$02                ; test X0087.1 (indicates MAF fault)
                beq         .LE8C0              ; branch ahead if no MAF fault

;------------------------------------------------------------------------------
;                      MAF Fault Substitution Code
;
; This code executes when the MAF Fault Bit is set. Since the load based row
; index cannot be calculated without a valid MAF reading, an alternate method
; is needed. This method estimates the fuel requirement based only on throttle
; position and engine temperature. The data values that are used to tailor
; the results are stored in the data portion of the PROM. The code is set up
; for different open and closed map values, however, both sets of values are
; identical. The end result is a 16-bit value in the AB register set. The
; normal fuel map code block is then bypassed.
;
;------------------------------------------------------------------------------
                ldd         throttlePot         ; load 10-bit TPS value
                subd        throttlePotMinimum  ; subtract TPmin
                bcc         .LE87A              ; branch if result is positive
                
                ldd         #$0000              ; else, limit value to zero

.LE87A          lsrd                            ; shift right twice so that
                lsrd                            ; top bits are in B register
                ldaa        fuelMapNumber       ; load fuel map number
                beq         .LE885              ; branch if map 0

                cmpa        #$04                ; compare with 4
                bcs         .LE89E              ; branch if less than 4
;-------------------------
; Fuel Maps 0, 4 and 5
;-------------------------
.LE885          ldaa        coolantTempCount    ; load ECT sensor count
                cmpa        $C221               ; value is $47 (56 C or 138 F)
                bcs         .LE895              ; branch if ECT is hotter
                
                ldaa        $C222               ; value is $1E
                mul                             ; mpy top 8 bits of TPS by $1E
                addd        $C223               ; value is $1000, add this 16-bit value
                bra         .LE8B5              ; branch ahead

.LE895          ldaa        $C225               ; value is $24
                mul                             ; mpy top 8 bits of TPS by $24
                addd        $C226               ; value is $0E00, add this 16-bit value
                bra         .LE8B5              ; branch ahead
;-------------------------
; Fuel Maps 1, 2 and 3
;-------------------------
.LE89E          ldaa        coolantTempCount    ; load ECT sensor count
                cmpa        $C228               ; value is $47 (56 C or 138 F)
                bcs         .LE8AE              ; branch if ECT is hotter
                
                ldaa        $C229               ; value is $1E
                mul                             ; mpy top 8 bits of TPS by $1E
                addd        $C22A               ; value is $1000, add this 16-bit value
                bra         .LE8B5              ; branch ahead

.LE8AE          ldaa        $C22C               ; value is $24
                mul                             ; mpy top 8 bits of TPS by $24
                addd        $C22D               ; value is $E000, add this 16-bit value
;-------------------------
; Common code
;-------------------------
.LE8B5          cmpa        #$1B                ; compare MSB of result with $1B
                bcs         .LE8BB              ; branch if value is lower
                
                ldaa        #$1B                ; else, limit to $1Bxx maximum

.LE8BB          asld                            ; 2x
                asld                            ; 4x
                asld                            ; 8x (max value is $DFF8)
                bra         .LE921              ; branch to skip normal fuel map code and go
                                                ; to fuel value filtering
                
;---------------------------------------------------------------------------------------------------
;	         Use Row and Column Indexes to calculate 16-bit Fueling Value from Table 
;	
; This code section is executed only when the MAF fault bit is not set. The index register (X)
; contains the fuel map address pointer. The value is calculated here by first calculating the
; contribution of each of the 4 table values surrounding the actual fueling point and then adding
; the four values.
;
;---------------------------------------------------------------------------------------------------
.LE8C0          ldaa        fuelMapLoadIdx      ; load fuel map row index ($70 max)
                anda        #$F0                ; mask upper nibble (4-bit row index)
                ldab        fuelMapSpeedIdx     ; load fuel map column index ($F0 max)
                lsrb                            ; shift upper nibble of column index into low position
                lsrb
                lsrb
                lsrb
                aba                             ; add B to A (offset of upper left corner of box)
                tab                             ; xfr A to B (value range: 0x00 thru 0x7F)
                bne         .LE8D0              ; branch if not zero
                
                ldab        #$60                ; else, it was zero so load $60 as default

.LE8D0          abx                             ; X = fuelMapPtr, add offset into map

                ldaa        fuelMapSpeedIdx     ; load column index
                anda        #$0F                ; mask lower nibble of the column index
                staa        $00C9               ; and store it in X00C9
                ldaa        fuelMapLoadIdx      ; load row index
                anda        #$0F                ; mask lower nibble of the row index
                staa        $00C8               ; and store it in X00C8
                ldaa        #$10                ; load A with 16 decimal
                tab                             ; transfer it to B
                suba        $00C8               ; subtract X00C8 from $10
                subb        $00C9               ; subtract X00C9 from $10
                std         $00C8               ; store A at X00C8 and B at X00C9
                mul                             ; mpy A and B (value should be <= $FF and contained in B only)
                ldaa        $00,x               ; load upper left value from map into A
                mul                             ; mpy A and B
                std         $00CC               ; store 16-bits at X00CC/CD (upper left contribution value)

                bne         .LE8F7              ; branch ahead if result is not zero
                ldaa        $00,x               ; if zero, load value from map again
                bra         .LE921              ; and branch to filtering section with this value
                
;-------------------------
.LE8F2          ldd         $00CE               ; these 2 lines have nothing to do with this section of code
                jmp         .LE967              ; it was just a convenient place to put a jump (used below)
;-------------------------

.LE8F7          ldaa        fuelMapLoadIdx      ; load fuel map row index
                anda        #$0F                ; mask to get low nibble
                ldab        $00C9               ; X00C9 is $10 minus lower nibble of column index
                mul                             ; multiply the two 4-bit values
                ldaa        $10,x               ; get value from next row in table (same column)
                mul                             ; multiply table value by B
                std         $00CE               ; store 16-bits at X00CE/CF (lower left contribution value)

                ldaa        $00C8               ; load high byte of previous multiply
                ldab        fuelMapSpeedIdx     ; load fuel map column index 
                andb        #$0F                ; mask to get low nibble
                mul                             ; multiply
                ldaa        $01,x               ; get value from next column up in table
                mul                             ; multiply
                std         $00C8               ; store 16-bits at X00C8/C9 (upper right contribution value)

                ldaa        fuelMapSpeedIdx     ; load fuel map column index
                anda        #$0F                ; mask to get low nibble
                ldab        fuelMapLoadIdx      ; load fuel map row index
                andb        #$0F                ; mask to get low nibble
                mul                             ; multiply (result < $FF so it's contained in B only))
                ldaa        $11,x               ; load value from next row and column
                mul                             ; multiply (AB = lower right contribution value)

                addd        $00CC               ; add upper left  contribution
                addd        $00C8               ; add upper right contribution
                addd        $00CE               ; add lower left  contribution
                
;---------------------------------------------------------------------------------------------------
;                           Filtering of Uncompensated Fuel Value
;
; Under certain conditions, the calculated fuel value if filtered to make it change more smoothly.
; This is done by adding 3 parts old value with 1 part new value and dividing by 4.
;
; Bit X008A.7 can be set in the Throttle Direction & Rate code.
;
;---------------------------------------------------------------------------------------------------
.LE921          std         $00CE               ; store the uncompensated fueling value
                ldaa        $008A               ; load bits value
                bita        #$40                ; test X008A.6 (init to 1, 0 = timeout)
                bne         .LE8F2              ; if not timed out, branch to load X00CE/CF and jump to Phase 1 comp
                
                bita        #$80                ; test X008A.7 (may indicate a large difference in TPS)
                beq         .LE8F2              ; if clr, branch to load X00CE/CF and jump to Phase 1 comp
                
                anda        #$7F                ; clr X008A.7
                staa        $008A               ; store bits value
                clra                            ; clr A
                staa        $00CC               ; clear X00CC (for next section)
                ldaa        $C7D7               ; data value is $00 (a code control value??)
                bne         .LE949              ; does not branch
                
                ldaa        $008B               ; load bits value
                bita        #$01                ; test X008B.0 (road speed > 4 KPH)
                bne         .LE949              ; branch if road speed > 4
                
                ldaa        $0086               ; load bits value
                bita        #$80                ; test X0086.7
                beq         .LE949              ; if zero, branch to continue
                
                ldd         $00CE               ; load uncompensated fueling value
                bra         .LE967              ; branch to Phase 1 comp
;-----------------------
; Filtering starts here                
;-----------------------
.LE949          ldd         $0080               ; load previous fueling value
                asld                            ; double the value
                rol         $00CC               ; rotate left (carry is included)
                addd        $0080               ; add previous fueling value (now 3X the value)
                bcc         .LE956              ; branch if no rollover
                
                inc         $00CC               ; rollover, so increment MSB

.LE956          addd        $00CE               ; add the new fueling value (3 old, 1 new)
                bcc         .LE95D              ; branch if no rollover
                
                inc         $00CC               ; rollover, so increment MSB again

                                                ; this part divides 16-bit value by 4
.LE95D          lsr         $00CC               ; logical shift right (lsb into carry)
                rora                            ; rotate right A
                rorb                            ; rotate right C
                lsr         $00CC               ; logical shift right (lsb into carry)
                rora                            ; rotate right A
                rorb                            ; new filtered fueling value is now in AB

;---------------------------------------------------------------------------------------------------
;                               Phase 1 Compensation
;
; At this point, the uncompensated 16-bit fuel value is calculated and is in the AB register set.
; The range of this value is determined by the range of values in the fuel map. For example, if
; the lowest and highest values in the fuel map are $14 and $FF, the range will be $1400 to $FF00
; or 5120 to 65,280 decimal.
;
; When the 16-bit multiply routine is called, it multiplies AB by the value in X00CA/CB. The earlier
; calculated compensation factor (time, temperature, throttle & Lambda) is currently in X00CA/CB.
;
; These are the steps that happen here:
;
;    1) Mpy X0080/81 by X00CA/CB (fuel map value by compensation factor)
;    2) Mpy value by 4X but limit to $FFFF
;    3) Mpy by fuel map multiplier (previously stored in X2008/09
;    4) Double the value
;    5) Limit to $FF00
;
;---------------------------------------------------------------------------------------------------

.LE967          std         $0080               ; save new fuel value here for use next time
                jsr         mpy16               ; mpy AB by X00CA/CB
                asld                            ; double the value (MSB becomes carry)
                bcs         .LE972              ; if value > $FFFF, branch ahead to limit to $FFFF
                
                asld                            ; double the value again
                bcc         .LE975              ; limit to $FFFF again, else branch ahead

.LE972          ldd         #$FFFF              ; limit value to $#FFFF

.LE975          std         $00CA               ; store for multiplication with fuel map multiplier
                ldd         $2008               ; fuel map multiplier value
                jsr         mpy16               ; mpy AB by X00CA/CB
                asld                            ; double the value (MSB becomes carry)
                bcc         .LE983              ; branch if carry clr
                
                ldd         #$FF00              ; limit value to $FF00 (65280 dec)
                
;---------------------------------------------------------------------------------------------------
;                       Phase 2 Compensation (long term trim adjustment)
;
; The 16-bit long term trim value is applied here.
;
; One count is added or subtracted to the fueling value for every $80 (128 dec) counts from the 32K
; neutral point. The max adjustment is $00FF (positive) or $FF00 (negative). That equals +255 to
; -256 in decimal.
;
; During cranking a special fuel value is used and code jumps to here bypassing fuel map use,
; filtering and Phase 1 compensation.
;
; The data value at XC0A0 is actually a code control value that's used in several places in the
; software. Here, bit 7 is tested and if the value is zero, the long term trim adjustment is
; skipped. This value is normally $80, which enables the long term adjustment.
;
;---------------------------------------------------------------------------------------------------
.LE983          std         $00CC               ; store partially compensated fuel value in X00CC/CD

                ldaa        $C0A0               ; data value is $80 (code control byte)
                bpl         .LE9A8              ; msb set, so does not branch to next section
                
                ldd         longLambdaTrimR     ; load right long term trim value
                tst         $0088               ; test bank indicator bit
                bpl         .LE993              ; if right, branch to use this value

                ldd         longLambdaTrimL     ; else, load the left bank value

.LE993          asld                            ; double the value (msb into carry flag)
                tab                             ; xfer A to B (carry flag not affected)
                bcs         .LE9A3              ; branch if value was $8000 or higher 
                
                ldaa        $008C               ; reduce fuel
                bita        #$08                ; test X008C.3 (this bit forces open loop)
                beq         .LE99F              ; if zero, branch to continue
                
                ldab        #$FF                ; create value of -1 ($FFFF), basically neutral

.LE99F          ldaa        #$FF                ; create negative value
                bra         .LE9A4              ; branch

.LE9A3          clra                            ; create positive value

.LE9A4          addd        $00CC               ; add adjustment to fuel value (range is +255 to -256)
                std         $00CC               ; store in-process fuel value

;---------------------------------------------------------------------------------------------------
;                        Phase 3 Adjustment (boost or reduce fuel)
;
; This section boosts the fuel value to 1.25 or reduces it to 0.75 under certain conditions.
; This still needs to be investigated and understood better.
;
;---------------------------------------------------------------------------------------------------

.LE9A8          ldaa        ignPeriod           ; load ignition period (MSB)
                cmpa        #$07                ; compare with $07 (equivalent to 4185 RPM)
                bcs         .LE9F2              ; branch to skip section if eng spd > 4185 RPM

                ldd         $00D2               ; load X00D2/D3 (2 bytes of bank related bits)
                tst         $0088               ; test bank indicator bit
                bmi         .LE9DC              ; if set, branch to left bank
;--------------
; Right Bank
;--------------
                bitb        #$15                ; test X00D3 bits 4, 2, 0
                bne         .LE9F2              ; if any are set, branch to skip
                
                anda        #$55                ; mask X00D2 bits 6, 4, 2, 0
                beq         .LE9F2              ; if all are zero, branch to skip
                
                bita        #$50                ; test X00D2 bits 6 & 4
                bne         .LE9F2              ; if either is set, branch to skip
                
                cmpa        #$05                ; test X00D2 bit 2 & 0 (6 & 4 must be zeros)
                beq         .LE9F2              ; if both are set, branch to skip
                
                cmpa        #$01                ; test X00D2 bit 0
                beq         .LE9D1              ; if bit is clear branch to 0.75 fuel
                                                ;         else fall thru to 1.25 fuel
;--------------
; 1.25 Fuel
;--------------
.LE9C9          ldd         $00CC               ; load fuel value
                lsrd                            ; div by 4
                lsrd
                addd        $00CC               ; add original value
                bra         .LE9F4              ; branch to Phase 4
;--------------
; 0.75 Fuel
;--------------
.LE9D1          ldd         $00CC               ; load fuel value
                lsrd                            ; div by 4
                lsrd
                subd        $00CC               ; subtract original value (now it's negative)
                jsr         absoluteValAB       ; convert to positive (absolute value)
                bra         .LE9F4              ; branch to Phase 4
;--------------
; Left Bank
;--------------
.LE9DC          bitb        #$2A                ; test X00D3 bits 5, 3, 1
                bne         .LE9F2              ; if any are set, branch to skip
                
                anda        #$AA                ; mask X00D2 bits 7, 5, 3, 1
                beq         .LE9F2              ; if all are zero, branch to skip
                
                bita        #$A0                ; test X00D2 bits 7 & 5
                bne         .LE9F2              ; if either is set, branch to skip
                
                cmpa        #$0A                ; test X00D2 bits 3 & 1
                beq         .LE9F2              ; if both are set, branch to skip
                
                cmpa        #$02                ; test X00D2 bit 1
                beq         .LE9D1              ; if bit is clear, branch to 0.75 fuel
                
                bra         .LE9C9              ; branch to 1.25 fuel
                
;---------------------------------------------------------------------------------------------------
;                       Phase 4 (final adjustment, main voltage)
;
; This makes the final fueling compensation based on main voltage. The road speed limit bit is also
; checked for the right bank only. Only the right bank shuts off when the speed limit is reached.
;
;---------------------------------------------------------------------------------------------------
.LE9F2          ldd         $00CC               ; Load the partially compensated fueling value


.LE9F4          addd        mainVoltageAdj      ; used to adjust inj. pulse based on main voltage
                bcc         .LE9FB              ; branch to continue if value did not roll over

                ldd         #$FFFF              ; limit value to $FFFF

.LE9FB          std         compedFuelingVal    ; store final fuel value at X0082/83
                std         $00CC               ; also store it temporarily at X00CC/CD
                
                
IF BUILD_R3365
;-----------------------------------------------------------
; Defender Only (R3365)
;-----------------------------------------------------------
	   	        ldaa	    #$27
	   	        staa	    AdcControlReg1
	   	        ldaa	    #$C8
	   	        staa	    AdcDataLow
	   	        jsr	        LFA46
ELSE

                jsr         rdSpdCompTest       ; road speed test, loads X2012 in B before returning
	   	        
ENDC
                
                
                tst         $0088               ; test for bank
                bmi         .LEA73              ; if X0088.7 is high, branch to left bank

IF BUILD_TVR_CODE
                ; nothing
ELSE                
;-----------------------------------------------
; Road speed limiting code (not in TVR code)
;-----------------------------------------------
                ldaa        $2004               ; test X2004.0 (1 = road speed over limit)
                bita        #$01                ; if set, skips injector refresh for right bank and
                bne         .LEA71              ; branch down to toggle bank bit
ENDC

;-----------------------------------------------
; Right Bank Timer Setup (X0088.7 = 0)
;-----------------------------------------------
                ldaa        timerCntrlReg1      ; load timer control register 1
                anda        #$FE                ; clr OLVL1 (P21 for even Injector Bank)
                staa        timerCntrlReg1
                ldaa        $201F               ; this bit is set in TPS routine
                bita        #$04                ; test X201F.2 (does this mean TPS code is doing a fuel adjust?)
                beq         .LEA3B              ; branch ahead if if X201F.2 is low

                anda        #$FB                ; X201F.2 was set, clear it
                staa        $201F               ; store it
                ldaa        timerStsReg         ; load timer status register
                bita        #$08                ; test output compare flag (OCF1)
                bne         .LEA3B              ; branch ahead if OCF1 is high

                ldd         ocr1High            ; OCF1 is low
                addd        $00CC               ; add fueling value
                std         ocr1High            ; this clears OCF1
                ldaa        timerCntrlReg1      ; load timer control register 1
                oraa        #$01                ; set OLVL1 (Output Level 1)
                staa        timerCntrlReg1      ; write it back
                cmpa        timerStsReg         ; compare status and control regs??
                ldd         ocr1High            ; load 16-bit output compare value
                std         ocr1High            ; this sequence clears OCF1
                jmp         .LEAD5              ; jump ahead to toggle bank bit and fall into RPM calc

                                                ; code branches here from above if 201F.2 is low or OCF1 is high
.LEA3B          ldaa        timerCSR
                staa        $00CA               ; store Timer Control Status reg in 00CA
                ldd         counterHigh         ; get current counter value
                addd        #$0013              ; add 19
                std         ocr1High            ; store in output compare reg
                cmpa        timerStsReg         ;
                std         ocr1High            ; store it again (this sequence clears the OCF1)
                addd        $00CC
                std         $00CE
                ldaa        $00CA
                bita        #$20                ; test TOF (timer overflow flag)
                beq         .LEA63              ; branch ahead if no overflow

                inc         $2001               ; overflow, so increment both overflow counters
                bne         .LEA5C
                dec         $2001               ; clip at FF

.LEA5C          ldab        $00B2               ; inc 00B2 but not GT $FF
                incb
                beq         .LEA63
                stab        $00B2

.LEA63          ldaa        timerCntrlReg1
                oraa        #$01                ; set OLVL1 (Output Level 1)
                staa        timerCntrlReg1
                ldd         $00CE
                std         ocr1High            ; store X00CE/CF in the 16-bit Output Compare Register 1
                cmpa        timerStsReg
                std         ocr1High            ; this sequence clears OCF1

.LEA71          bra         .LEAD5              ; LEAD5 = toggle bank bit and fall into RPM calc
;-----------------------------------------------
; Left Bank Timer Setup (X0088.7 = 1)
;-----------------------------------------------

.LEA73          ldaa        timerCntrlReg1
                oraa        #$04                ; set OLVL3 (P12 --> Even Injector Bank)
                staa        timerCntrlReg1
                ldaa        $201F
                bita        #$08                ; test 201F.3 (1 means TP is doing a fuel adjust)
                beq         .LEA9F              ; branch ahead if bit 3 is low

                anda        #$F7                ; bit 3 was set, clear it
                staa        $201F
                ldaa        timerStsReg
                bita        #$20                ; test bit 5 in timerStsReg (OCF?)
                bne         .LEA9F
                ldd         ocr3high
                addd        $00CC               ; <-- Adjust Value??
                std         ocr3high            ;
                ldaa        timerCntrlReg1
                anda        #$FB                ; clr OLVL3
                staa        timerCntrlReg1
                cmpa        timerStsReg
                ldd         ocr3high
                std         ocr3high            ; this clrs OCF3
                bra         .LEAD5              ; LEAD5 = toggle bank bit and fall into RPM calc


.LEA9F          ldaa        timerCSR
                staa        $00CA
                ldd         counterHigh
                addd        #$0013
                std         ocr3high
                cmpa        timerStsReg
                std         ocr3high
                addd        $00CC
                std         $00CE
                ldaa        $00CA
                bita        #$20
                beq         .LEAC7

                inc         $2001               ; overflow, so increment both overflow counters
                bne         .LEAC0
                dec         $2001

.LEAC0          ldab        $00B2               ; inc 00B2 but not GT $FF
                incb
                beq         .LEAC7
                stab        $00B2


.LEAC7          ldaa        timerCntrlReg1
                anda        #$FB                ; clr OLVL3
                staa        timerCntrlReg1
                ldd         $00CE
                std         ocr3high
                cmpa        timerStsReg
                std         ocr3high

;-----------------------------------------------
; Back to common bank code
;-----------------------------------------------

.LEAD5          ldaa        $0088
                eora        #$80                ; <-- Toggle right/left bank bit
                staa        $0088
                
;------------------------------------------------------------------------------
;                *** Calculate Engine RPM Bracket (column index) ***
;
; This code compares the measured ignition pulse period with the 16-bit values
; stored in the data table located at 0xC800. This results in the fuel map
; indexing value which is based on engine speed. The upper nibble of this value
; is the coarse column index (0 thru 15 for the 16 columns).
;
; The second part of this code uses the filtered ignition pulse value
; to calculate the engine RPM (up to 1950 RPM). The algorithm used
; for the division is described in the M6800 Microprocessor Applications
; Manual (1975). The pulse period is divided by 7,500,000 to get RPM.
;
;------------------------------------------------------------------------------

.LEADB          ldx         #rpmTable
                ldaa        #$0F                ; load length of data table
                staa        $00CA               ; store $0F into 00CA (general purpose var)
                                                ; * Start Loop *
.LEAE2          ldd         $00,x               ; value from C800 table (1st value is $0553 or 5502 RPM)
                subd        ignPeriod
                bcc         .LEAF5              ; branch out if period is LT table value (RPM is higher)
                ldab        #$04                ; add 04 to index
                abx                             ; add B ($04) to X ($C800) = $C804
                dec         $00CA               ; decrement table length counter
                bpl         .LEAE2              ; *  End  Loop * (loop back if not end of table)
                clr         fuelMapSpeedIdx
                bra         .LEB1F              ; table ran out, branch way down

.LEAF5          std         $00C8               ; 00C8/C9 is table entry minus current ignition period
                ldaa        $00CA               ; 00CA is table entry counter ($F->0) and it becomes
                asla                            ;   the fuel map column index upper nibble
                asla
                asla
                asla
                staa        $00CA               ; index shifted to upper nibble
                ldaa        $02,x               ; load value from table column 3 ($40, $00 or $80)
                bpl         .LEB0B              ; bra if value is not $80
                ldd         $00C8               ; value is $80, reload speed delta from above
                lsrd
                lsrd
                lsrd
                lsrd                            ; shift speed delta down to lower nibble
                bra         .LEB15
                                                ; value is $40 or $00
.LEB0B          bita        #$40                ; test bit 6
                beq         .LEB13
                ldab        $00C8               ; value is $40, reload speed delta from above (no shift)
                bra         .LEB15
                                                ; value is $00
.LEB13          ldab        $00C9               ; reload just the low byte of speed delta (no shift)

.LEB15          ldaa        $03,x               ; load right-most value from table
                mul                             ; mpy A (table value) by B (speed delta)
                oraa        $00CA               ; or it into the low nibble of the column index
                staa        fuelMapSpeedIdx
IF BUILD_R3365
                ; nothing
ELSE
                jsr         rdSpdCompTest       ; road speed test, reloads X2012 in B before returning
ENDC                

.LEB1F          jsr         keepAlive
;------------------------------------------------------------------------------
;                        *** Calculate Engine RPM ***
;
;    Now use filtered PW value to calculate RPM
;    This is a division loop.
;------------------------------------------------------------------------------
                ldd         ignPeriodFiltered
                cmpa        #pwRpmComputeLimit  ; don't compute the RPM beyond this speed (2092 RPM)
                bhi         .computeRPM
                ldd         #compRpmMaxConst    ; instead used this fixed value (1950 RPM)
                bra         .storeEngineRPM

.computeRPM     ldd         #$7270              ; <-- code branches here if eng RPM is GT 2092
                std         $00C8               ; store $7270 in 00C8/C9
                ldd         #$00E0              ; store $E0 in 00CA
                stab        $00CA               ; C8/C9/CA is now the 24-bit value 0x7270E0 (7,500,000 decimal)
                tab                             ; transfer a to b to clear b
                ldx         #$0018              ; load index with 24 for 24-bit divide loop

                                                ; * Start Division Loop *
.rpmDivLoop     asl         $00CA               ; arith shift left (bit 7 goes into carry)
                rol         $00C9               ; rotate left (carry into b0, b7 into carry)
                rol         $00C8               ; rol again effectively does a left shift on the 24-bit value
                rolb
                rola
                subd        ignPeriodFiltered
                bcc         .LEB4E
                addd        ignPeriodFiltered
                bra         .LEB51

.LEB4E          inc         $00CA

.LEB51          dex                             ; decrement counter
                bne         .rpmDivLoop

                ldd         $00C9
                bra         .storeEngineRPM

                ldx         #$0007

.LEB5B          addd        engineRPM
                dex
                bne         .LEB5B
                lsrd
                lsrd
                lsrd                            ; div by 8

.storeEngineRPM std         engineRPM

;------------------------------------------------------------------
;            *** High Road Speed Code ***
;
; Check road speed and condition 202B and 2004.0 accordingly
; 202B is set to $AA  when road speed is GTE $C4 (122 MPH)
; 202B is set to zero when road speed is LT  $C0 (119 MPH)
; 2004.0 is also set or cleared at the same time
;------------------------------------------------------------------
                ldaa        roadSpeed
                ldab        $2004               ; bits
IF BUILD_R3365                
                suba        #$AF                ; 175 KPH
ELSE
                suba        #$C4                ; 196 KPH (122 MPH)
ENDC                
                bcs         .roadSpeedLo

                ; road speed is greater than
                orab        #$01                ; set 2004.0
IF BUILD_R3365                
                ldaa        #$91
ELSE
                ldaa        #$AA
ENDC                
                
                staa        $202B               ; set $202B to $AA to indicate high speed

.LEB76          stab        $2004
                bra         .LEB86              ; branch to next section

IF BUILD_R3365                
.roadSpeedLo    cmpa        #$F9                ; after subtract (above), check for -6
ELSE
.roadSpeedLo    cmpa        #$FC                ; after subtract (above), check for -4 (hysteresis??)
ENDC
                bcc         .LEB86              ; branch to next section if road speed is GT 119 MPH
                andb        #$FE                ; clr 2004.0
                clr         $202B               ; set 202B to zero
                bra         .LEB76              ; branch up to store X2004 and branch to next section

;------------------------------------------------------------------
; This section executes only after the 009C timeout and if 0089.0
; and 0089.1 are both zero.
;------------------------------------------------------------------

.LEB86          ldaa        $008A
                bita        #$40                ; test 008A.6 (0 = startup timeout, 009C 1Hz down-counter)
                bne         .LEB92
                ldaa        $0089
                anda        #$03                ; mask 0089.1 and 0089.0
                beq         .LEB95              ; branch ahead (to skip jump) if both are zero

.LEB92          jmp         .LEC53              ; jump way down to next section

;------------------------------------------------------------------
;	            *** Check Engine RPM Limit ***
;
;    Bit 0x0086.5 is normally set and is cleared when over limit
;    Bit 0087.7 is set & clrd here (bit forces open loop)
;
; A safety margin of $1B equates to about 100 RPM
; A safety margin of $0F equates to about  75 RPM
;------------------------------------------------------------------
.LEB95          ldd         ignPeriodFiltered   ; load 16-bit filtered spark period
                subd        rpmLimitRAM         ; subtract (X200C) RPM limit
                bcc         .LEBA4              ; branch if RPM is OK
                
                ldaa        $0086               ; <-- if here, eng speed is over limit
                anda        #$DF                ; clear X0086.5 to indicate RPM over limit (bit is normally 1)
                staa        $0086               ; store it
                bra         .LEC1A              ; branch

.LEBA4          cmpa        #$00                ; is upper byte of remainder non-zero?
                bne         .LEBAD              ; if so, plenty of margin, so branch to RPM OK
                
                cmpb        $200B               ; compare low byte of remainder with safety margin
                bcs         .LEC1A              ; if remainder < safety margin, branch down

.LEBAD          ldaa        ignPeriodFiltered   ; <-- RPM is OK, load spark period again
                cmpa        $C137               ; data value is $10 (about 1831 RPM)
                bhi         .LEBBA              ; branch ahead if RPM < 1831
                
                ldaa        $0089               ; <-- RPM > 1831
                oraa        #$08                ; set X0089.3 (this bit only used in this section)
                staa        $0089
                
.LEBBA          ldaa        $0089               ; load bits value
                bita        #$08                ; test X0089.3 (this bit only used in this section)
                beq         .LEBDF              ; branch ahead if bit is zero
                
                ldaa        coolantTempCount    ; if here RPM > 1831, load ECT sensor count
                ldab        $0086               ; load bits value
                orab        #$20                ; set X0086.5 to indicate RPM is under limit
                stab        $0086               ; store it
                tstb                            ; test X0086.7
                bmi         .LEBDA              ; branch if set
                
                cmpa        $C17E               ; 4th col coolant temp table ($23 or 87 deg C)
                bcc         .LEBD5              ; branch if cooler
                
                ldd         $C14B               ; <-- warmer than 87 C, load value $0064
                bra         .LEBD8              ; branch
                
.LEBD5          ldd         $C149               ; <-- cooler than 87 C, load value $0000
.LEBD8          bra         .LEBE2              ; branch

.LEBDA          cmpa        $200E               ; <-- X0086.7 is set, compare with X200E
                bcs         .LEBFD              ; branch if hotter
;----------------------------------------

.LEBDF          ldd         $C14D               ; load value $008C

.LEBE2          tst         $0089               ; test X0089.7
                bpl         .LEC1A              ; branch ahead if X0089.7 is clear

                addd        throttlePot         ; add 10-bit TPS value
                std         $0061               ; store as top 2 bytes of 24-bit value
                ldd         throttlePot         ; load 10-bit TPS value
                std         $00E3               ; store TPS value temporarily
                ldaa        $0089               ; load bits value
                anda        #$7F                ; clear X0089.7
                staa        $0089               ; store it
                ldaa        $00DC               ; load bits value
                oraa        #$40                ; set X00DC.6
                staa        $00DC               ; store it
                bra         .LEC4D              ; branch
;----------------------------------------
.LEBFD          ldab        $008B               ; load bits value
                lsrb                            ; shift X008B.0 into carry (road speed > 4)
                bcc         .LEBDF              ; branch back if road speed < 4 KPH
                
                ldaa        #$FF                ; <-- road speed > 4 KPH
                ldab        $0087               ; load bits value
                orab        #$80                ; set X0087.7 (this bit forces open loop)
                stab        $0087               ; store it
                ldab        $205B               ; load bits value 
                orab        #$03                ; set X205B.1 and X205B.0 (bank related bits)
                stab        $205B               ; store it
                staa        $00C1               ; reset this variable to $FF (loaded earlier)
                ldaa        $0089               ; load bits value
                oraa        #$80                ; set X0089.7
                staa        $0089               ; store it (end normal RPM code)
;----------------------------------------
.LEC1A          ldaa        $00DC               ; code above branches here when RPM is above limit
                bita        #$40                ; test X00DC.6
                beq         .LEC38              ; branch if bit is zero
                
                anda        #$BF                ; clear X00DC.6
                oraa        #$80                ; set X00DC.7
                staa        $00DC               ; store it
                ldd         throttlePot         ; load 10-bit TPS value
                subd        $00E3               ; subtract TPS value stored earlier
                bcs         .LEC38              ; branch if negative (TPS value < stored value)
                
                subd        $C1F4               ; still positive, subtract data value $0023
                bcs         .LEC38              ; now branch if negative
                
                ldd         throttlePot         ; still positive
                subd        $C1F6               ; subtract data value $0000
                std         $0061               ; store as top 2 bytes of 24-bit value


.LEC38          ldaa        coolantTempCount    ; load ECT sensor count
                ldab        ignPeriodFiltered   ; load filtered spark period (MSB only)
                cmpa        $200F               ; compare ECT with X200F
                bcs         .LEC48              ; branch if hotter
                
                cmpb        $C138               ; compare B with value $14 (approx 1400 RPM)
                bcs         .LEC53              ; branch if RPM > 1400
                
                bra         .LEC4D              ; if here, RPM < 1400, branch

.LEC48          cmpb        $C139               ; compare B with value $17 (approx 1250 RPM)
                bcs         .LEC53              ; branch if RPM > 1250

.LEC4D          ldab        $0089
                andb        #$F7                ; clear X0089.3 (this bit only used in this section)
                stab        $0089
;------------------------------------------------------------------
;   This section uses the 2028 down counter
;------------------------------------------------------------------

.LEC53          ldaa        $0086
                bmi         .LEC84              ; branch ahead if 0086.7 is one

                sei                             ; <-- set interrupt mask
                ldaa        $004F               ; load battery backed value
                adda        $0072               ; stayed 128 (exc for spike to 37 at RR end)
                bcs         .LEC6B
                
                adda        #$B4                ; 180 dec
                tab
                bcs         .LEC67
                
                ldaa        #$7F                ; limit value to 127
                bra         .LEC76

.LEC67          ldaa        #$80
                bra         .LEC76

.LEC6B          adda        #$B4
                tab
                bcs         .LEC74
                
                ldaa        #$80
                bra         .LEC76

.LEC74          ldaa        #$81

.LEC76          std         $00C8
                ldd         $2053               ; a 16-bit counter?
                subd        $00C8
                bcs         .LEC84
                
                ldd         $00C8
                std         $2053               ; value starts at 32K and climbs to a plateau

.LEC84          cli                             ; <-- clr interrupt mask


IF BUILD_R3365
;-----------------------------------------------------------
; Defender Only (R3365)
;-----------------------------------------------------------
	   	        ldaa	    #$27
	   	        staa	    AdcControlReg1
	   	        ldaa	    #$C8
	   	        staa	    AdcDataLow
	   	        jsr	        LFA46
ELSE
                jsr         rdSpdCompTest       ; road speed test, loads X2012 in B before returning	   	        
ENDC

                ldaa        coolantTempCount
                cmpa        $C15F               ; value is $A0
                bcs         .LEC9D              ; branch ahead if coolant value is less than (hotter than)
                
                ldaa        $008B
                oraa        #$08                ; set 008B.3 (1 of 2)
                staa        $008B
                ldd         $C178               ; only referenced here, value is $5000
                std         $2028               ; some kind of down counter (1 of 3)
                bra         .LECB5

.LEC9D          cmpa        $C17E               ; inside coolant temp table (value is $23)
                bcc         .LECB5              ; branch ahead if coolant is GT (cooler than)
                
                ldd         $2028               ; some kind of down counter (2 of 3)
                beq         .LECAF
                subd        #$0001
                std         $2028               ; some kind of down counter (3 of 3)
                bra         .LECB5

.LECAF          ldaa        $008B
                anda        #$F7                ; clr 008B.3 (2 of 2) when down counter reaches zero
                staa        $008B
                                                ; (divider here? stppr mtr code below)

.LECB5          ldaa        iacMotorStepCount
                bne         .LED29              ; branch way down if not equal to zero
                ldaa        $0086
                oraa        $0085
                bmi         .LED29              ; branch down if either 0085.7 or 0086.7 is set
                
                ldaa        $008C
                bita        #$04                ; test 008C.2
                beq         .LECCE
                
                anda        #$FB                ; clr  008C.2
                staa        $008C
                ldx         #$0000              ; reset 00B5/B6 to zero
                stx         $00B5               ; 00B5/B6 is between -20 and about 60

.LECCE          ldx         $00B5
                inx                             ; increment 00B5/B6
                ldaa        coolantTempCount
                cmpa        #$AD
                bcs         .LECD8              ; branch ahead if CT is LT $AD
                
                inx

.LECD8          cpx         $C171               ; value is $003C (60 decimal)
                bcs         .LED27              ; branch ahead if 00B5 value is LT $003C
                
                jsr         LF9A1               ; the only call to this routine (calculates val in $006E)
                ldaa        $008B
                bita        #$08                ; test 008B.3
                beq         .LECFC
                
                ldab        $C186               ; val is $A0 (160 dec)
                subb        $006E               ; calc value based on coolant temp (100 -> 160)
                ldaa        $C15E               ; val is $0A
                sba                             ; subtract B from A
                bcs         .LECFC              ; branch ahead if B was GT A
                
                tab                             ; xfer A to B
                ldaa        #$80
                sba
                tab                             ; xfer A to B
                ldaa        $2048               ; initial (middle value) is 128
                sba                             ; subtract B from A
                bra         .LED01

.LECFC          ldaa        $2048               ; initial (middle value) is 128
                suba        #$80

.LED01          bne         .LED08

                clr         $0071               ; occasionally init to 6 and decremented to zero
                bra         .LED24

.LED08          bcs         .LED13

                clr         $0071               ; occasionally init to 6 and decremented to zero
                ldaa        $008A
                anda        #$FE                ; clr 008A.0 (stepper mtr direction bit, 0 = open)
                bra         .LED1E

.LED13          ldaa        $008A
                oraa        #$01                ; set 008A.0 (stepper mtr direction bit, 1 = close)
                ldab        $0071               ; occasionally init to 6 and decremented to zero
                beq         .LED1E
                
                decb
                stab        $0071               ; occasionally init to 6 and decremented to zero

.LED1E          staa        $008A
                ldaa        #$01
                staa        iacMotorStepCount

.LED24          ldx         #$0000              ; reset 00B5/B6 to zero

.LED27          stx         $00B5

.LED29          ldaa        $0085               ; test 0085.7 (indicates no or low eng RPM)
                bmi         .LED5F              ; branch if set (eng not running)
                ldab        $008A
                bitb        #$40                ; test 008A.6 (0 = startup timeout)                
                beq         .LED5F
                
                ldd         $C09A               ; $F830 (-2000 dec)
                std         $008E
                ldd         $C09C               ; $07D0 (+2000 dec)
                std         $0090
                ldaa        $0089
                oraa        #$07                ; set 0089 bits 2:0
                staa        $0089
                
;---------------------------------------
; Lots of timeout counter checks
;---------------------------------------
                ldx         #$009C              ; X009C was init from 3rd row of coolant table
                jsr         LF135               ; 1 Hz down counter for X009C
                ldaa        $009C               ; 009C decrements to zero at 1 Hz rate
                bne         .LED5F              ; branch ahead until 009C reaches zero

                ldaa        $008A
                anda        #$BF                ; clear 008A.6 (0 = startup timeout)
                staa        $008A
                ldaa        faultBits_49
                bita        #$40                ; Test for MAF Sensor Fault
                bne         .LED5F
                
                ldaa        $0087
                anda        #$FD                ; clr 0087.1 (indicates MAF fault)
                staa        $0087

IF BUILD_R3365
;-----------------------------------------------------------
; Defender Only (R3365)
;-----------------------------------------------------------
.LED5F	   	    ldaa	    #$27
	   	        staa	    AdcControlReg1
	   	        ldaa	    #$C8
	   	        staa	    AdcDataLow
	   	        jsr	        LFA46
ELSE

.LED5F          jsr         rdSpdCompTest       ; road speed test, reloads X2012 in B before returning
	   	        
ENDC

                ldaa        fuelMapNumber
                beq         .LED7F              ; branch ahead if map is zero
                
                cmpa        #$04
                bcc         .LED7F              ; branch ahead if map is 4 or 5
                
                ldaa        $2004               ; if here, map is open loop (1, 2 or 3)
                oraa        #$0C                ; set 2004 bits 3:2
                staa        $2004
                ldaa        $0086
                bita        #$04                ; test 0086.2
                beq         .LEDBC
                
                ldaa        $008A
                bita        #$40                ; test 008A.6 (0 = startup timeout)
                beq         .LED8C
;---------------------------------------

.LED7F          ldaa        $201D               ; counts down from $10 to zero (about 1 sec rate)
                beq         .LED8C
                
                ldx         #$201D
                jsr         LF151               ; down counter for X201D
                bra         .LEDBC
;---------------------------------------

.LED8C          ldaa        $2020               ; right bank startup timer (stayed zero for both RTs)
                beq         .LEDA4              ; branch ahead if X2020 reached zero
;---------------------------------------
                ldaa        $0089
                anda        #$03                ; mask 0089 bits 1:0
                beq         .LED9E              ; branch ahead if both bits are zero
                ldaa        $2004
                bita        #$04                ; test 2004 bit 2
                beq         .LEDA4

.LED9E          ldx         #$2020
                jsr         LF135               ; down counter for X2020
;---------------------------------------

.LEDA4          ldaa        $2021               ; left bank startup timer (stayed zero for both RTs)
                beq         .LEDBC              ; branch ahead if X2021 has reached zero
;---------------------------------------
                ldaa        $0089
                anda        #$03                ; mask 0089 bits 1:0
                beq         .LEDB6              ; branch ahead if both bits are zero
                
                ldaa        $2004
                bita        #$08                ; test 2004 bit 3
                beq         .LEDBC

.LEDB6          ldx         #$2021
                jsr         LF151               ; down counter for X2021
;---------------------------------------

.LEDBC          ldaa        #$FF                ; reset fuel pump delay
                staa        fuelPumpTimer
                ldaa        port1data
                anda        #$BF                ; P1.6 low (fuel pump ON)
                staa        port1data
                ldaa        $203C               ; 203C is a fault code delay counter
                beq         .LEDCF
                deca
                staa        $203C               ; decrem fault code delay counter

.LEDCF          jsr         LF018               ; only call to F018, alters values at 008E/8F, 0090/91

IF USE_4004_BIT4_FOR_ICI

                ldaa        i2cPort             ; [4] profiling code
                anda        #$EF                ; [2] 4004.4 low
                staa        i2cPort             ; [4]
ENDC                

                jmp         iciReentry
;------------------------------------------------------------------------------
                
code
