;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       ADC Routine - Road Speed - Channel 7 (8-bit conversion)
;
;   ADC service routines are entered with the newly measured ADC value in
;   X00C8/C9 (only X00C9 for 8-bit readings). The A accumulator also contains
;   the 8-bit reading.
;
;   There are two routines in this file.
;
;   adcRoutine7
;       This is the main road speed service routine. It conditions the 4 KPH
;   bit (for control of IACV), periodically writes the road speed and tests
;   for bad VSS (fault code 68).
;
;   rdSpdCompTest
;       This is called numerous times from many places in the ICI. Its
;   purpose is to catch or sample every VSS signal transition in order to
;   determine the VSS signal frequency and, thereby, the road speed.
;
;
;
;    From Land Rover Docs:
;
;    The Vehicle Speed Sensor is located on the left hand side of the frame
;    on early models, and on the left hand side of the transfer case on later
;    models. It informs the ECM when vehicle speed is above or below 3 mph.
;    This information is used by the ECM to ensure that the idle air control
;    valve (IACV) is moved to a position to prevent a stall when the vehicle
;    comes to a stop. DTC 68 will be displayed if the MAF is greater than 3V
;    at 2000-3000 RPMs.
;
;------------------------------------------------------------------------------
code

;------------------------------------------------------------------------------
;
;   Main Road Speed Service Routine
;
;   Road speed related variables are:
;
;   2001 - Road Speed latch counter (reset when > 13, takes approx 1 sec)
;   2002 - VSS signal transition counter
;   2003 - Road Speed in KPH
;
;------------------------------------------------------------------------------
adcRoutine7     staa        $00C8               ; now both C8 and C9 hold the 8-bit value
                ldab        $2001               ; latch counter, increments every 65 ms
                cmpb        #$0D                ; compare with 13
                bhi         .LD3A8              ; branch if X2001 > 13
                bcs         .LD3BA              ; branch if X2001 < 13
;------------------
; X2001 = 13
;------------------
                                                ; if here, X2001 = 13 (happens approx once per second)
                ldab        $202B               ; ICI sets this to $AA or $00 to indicate high road speed
                beq         .LD38A              ; branch if road speed is LT 119 to 122 MPH
IF BUILD_R3365
                ldab        #$96                ; 150 dec (approx 93 MPH)
ELSE                
                ldab        #$B0                ; 176 dec (approx 109 MPH)
ENDC                
                
                bra         .LD38D

                                                ; if here, road speed is LT 122 (or 119?)
.LD38A          ldab        $2002               ; latch transition counter as road speed

.LD38D          stab        roadSpeed           ; store actual road speed (or 176 KPH limit)
                beq         .LD3A5
                
                                                ; if here, VSS appears to be working (non-zero)
                inc         $207D               ; X207D looks like a fault delay (slowdown) counter
                ldab        $C258               ; this value is usually $0A
                cmpb        $207D               ; compare counter with $0A
                bcc         .LD3A8              ; branch ahead if counter < $0A
                
                ldab        $2047               ; else, clear internal fault bit
                andb        #$FB                ; clr X2047.2 (clear VSS fail bit)
                stab        $2047

.LD3A5          clr         $207D               ; clear the fault delay counter
;--------------------------------------
; Code branches here when X2001 > 13
;--------------------------------------                                                
.LD3A8          clrb                            ; reset both latch and transition counters
                sei                             ; these apparently must be clrd together, hence the mask
                stab        $2001               ; reset latch counter
                stab        $2002               ; reset transition counter
                cli                             ; clear interrupt mask
IF BUILD_TVR_CODE
                ; nothing
ELSE                
                ldaa        startupDownCount1Hz ; this down-counter is used by A/C routine and is
                beq         .LD3BA              ;  just decremented here
                deca                            ; decrement 1 Hz counter but not less than zero
                staa        startupDownCount1Hz
ENDC                

;--------------------------------------
; Code branches here when X2001 < 13
;--------------------------------------
                                                ; this sets/clears an idle control bit
.LD3BA          ldaa        $008B               ; load bits value
                ldab        roadSpeed           ; load road speed
                cmpb        #$04                ; compare road speed with 4
                bcc         .roadspeedGT4       ; branch to set X008B.0 if RS > 4
                
                anda        #$FE                ; clr X008B.0 (road speed < 4)
                bra         .LD3C9

.roadspeedGT4   oraa        #$01                ; set X008B.0 (road speed > 4)

.LD3C9          staa        $008B

;-----------------------------------------------------------
;        Fault Code 68 Test (Vehicle Speed Sensor)
;
;    If road speed value is zero and
;
;    1) MAF is > 3.0 volts
;    2) Engine speed is between 2250 and 3600 RPM
;                (2100 and 3600 for Griffith)
;    3) Fault 68 counter has been incremented enough times
;       (the value is stored in the data section at XC0CE/CF)
;-----------------------------------------------------------
                ldaa        roadSpeed           ; load road speed
                bne         .LD41A              ; branch to skip test if not zero

                ldd         mafDirectHi         ; if here, Road Speed is zero
                addd        mafDirectLo
                subd        #$04CE              ; this equals an average value of 3.0 volts
                bcs         .LD41A              ; abort test if airFlow sum avgs 3.0 volts
                
                ldaa        ignPeriodFiltered   ; load MSB of ignition period
                cmpa        #dtc68_minimumRPM   ; 2250 RPM for newer code, 2100 RPM for older code
                bcc         .LD41A              ; abort test if engine speed is lower than this
                
                cmpa        #$08                ; about 3600 RPM
                bcs         .LD41A              ; abort test if engine speed is greater than about 3600 RPM
                
                ldx         rsFaultSlowdown             ; load Road Speed fault delay counter
                inx                                     ; increment it
                stx         rsFaultSlowdown             ; store it
                cpx         rsFaultSlowdownThreshold    ; compare it with XC0CE/CF (usually $0800) 
                bcs         .LD41E                      ; branch to skip fault setting if less than this
                
                ldaa        $0088
                oraa        #$02                ; set X0088.1 (a Road Speed Sensor Fail bit)
                staa        $0088
                
                ldaa        faultBits_4C
                oraa        #$40                ; set Fault Code 68 (Vehicle Speed Sensor)
                staa        faultBits_4C
                
                ldaa        $2047
                oraa        #$04                ; set X2047.2 (another Road Speed Sensor Fail bit)
                staa        $2047
                
                bra         .LD41E              ; end of Road Speed Sensor fault check
                
;------------------------------------------------------------------------------
;   Road Speed Comparator (Level) Test
;
;   This is called from 8 different places in the ICI code. The ADC comparator
;   mode is used to determine if the sample of the incoming waveform is high or
;   low. The goal is to sample the waveform often enough to count every level
;   transition and, thereby, determine road speed.
;
;   The O2 sensor value (from X2012) is loaded into the B accumulator before
;   returning, although, it appear that only one call needs it.
;
;   Location X2049 increments from 0 to $FFFF while vehicle is moving. This is
;   effectively, a distance traveled indicator. X2049 may have something to do
;   with the Very Lean Mixture Fault (code 26) which may be unused.
;
;   This routine is only called from the ICI.
;
;------------------------------------------------------------------------------
rdSpdCompTest   ldaa        #$27                ; SC=0 PC=1  Set comparator mode on ch 7 (RS)
                staa        AdcControlReg1      ; 
                ldaa        #$C8                ; load level compare value
                staa        AdcDataLow          ; write comparitor value
                                                ; 1 if Vin is greater, 0 if Vin is less
.LD40D          ldaa        AdcStsDataHigh
                bita        #$40                ; test busy flag (BSY)
                bne         .LD40D              ; loop back if busy
                bita        #$20                ; test comparitor output bit (PCO)
                beq         .lowLevel
                bra         .highLevel
;---------------------------------------------------------------
                                                ; code above branches here when RS is not zero or when zero but
.LD41A          clra                            ; test passes (such as when stopped at a light)
                tab
                std         rsFaultSlowdown     ; clear RS fault slowdown counter
;---------------------------------------------------------------
                                                ; branched to from above when waiting for RS Sensor fail counts
                                                ;  or after failure bits are set
.LD41E          ldaa        $00C8               ; ADC level comparator value
                suba        #$C8
                bcs         .lowLevel
;---------------------------------------------------------------
.highLevel      ldaa        $008B
                oraa        #$80                ; set 008B.7 (Road Speed GT 124 MPH)
                staa        $008B
                bra         .rsReturn
;---------------------------------------------------------------
.lowLevel       ldaa        $008B
                bita        #$80                ; test 008B.7 (Road Speed GT 124 MPH)
                beq         .rsReturn
                anda        #$7F                ; else, clr 008B.7
                staa        $008B
                inc         $2002               ; (3 of 3) increment X2002 when road speed is not zero
                ldd         $2049               ; road speed counter
                addd        #$0001              ; increment road speed counter
                bcs         .loadO2AndRet       ; but stop at $FFFF
                std         $2049               ; (value ramps up while vehicle is moving)

.loadO2AndRet   ldab        $2012               ; load O2 sensor before returning

.rsReturn       rts
;------------------------------------------------------------------------------
code

