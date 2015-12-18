;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       ADC Routine - Main Relay Sense - Channel 8 (8-bit conversion)
;
;   ADC service routines are entered with the newly measured ADC value in
;   X00C8/C9 (only X00C9 for 8-bit readings). The A accumulator also contains
;   the 8-bit reading.
;
;   The raw ADC value is not saved in RAM. The raw value is used in a
;   calculation and the result is saved. The value in RAM goes up as
;   the voltage goes down. Here is the formula:
;
;        Y = ( (100)X^2 - (189)X  +  25608 ) / 4
;
;   Typically, the value starts around 1200 to 1400 (approx 12.6V) with
;   power on, spikes to around 2000 during cranking (low voltage) and settles
;   to around 900 to 950 (running voltage of 13+). The calculated value is
;   the last phase of compensation during fueling calculation.
;
;   It seems that if road speed is high, the voltage reading is saved as is,
;   but if the road speed is low, the reading is only altered by 1 count per
;   call.
;
;------------------------------------------------------------------------------

code
adcRoutine8     psha                            ; push ADC value
                ldab        $008B               ; X008B.6 is set when voltage is OK
                cmpa        #$8F                ; low voltage threshold
                bcs         .lowVoltage         ; branch to clr bit if below thrshold
                
                orab        #$40                ; set X008B.6 (Voltage OK)
                bra         .calcVoltageAdj

.lowVoltage     andb        #$BF                ; clr X008B.6 (Low Voltage)

.calcVoltageAdj stab        $008B               ; store X008B
                ldab        voltageMultB        ; for R3526 tune, value is $BD
                mul                             ; mpy main voltage 'A' by multiplier 'B'
                std         $00CA               ; store in X00CA/CB
                pula                            ; pull original ADC reading
                tab                             ; xfer A to B
                mul                             ; square the value
                ldab        voltageMultA        ; for R3526 tune, value is $64
                mul                             ; mpy upper 8 by this value
                subd        $00CA               ; subtract earlier value
                addd        voltageOffset       ; for R3526, value is $6408 (add this)
                lsrd                            ;
                lsrd                            ; div by 4
                std         $00CA               ; store in X00CA/CB
                ldaa        $008A
                bita        #$40                ; test X008A.6 (0 = startup timeout)
                bne         .LD0FF              ; branch ahead if bit is high
                
                ldaa        $00CA               ; reload A
                subd        mainVoltageAdj      ; subtract voltage ajustment
                bcs         .decVoltageAdj      ; branch if A is less
                
                ldd         mainVoltageAdj
                addd        #$0001              ; increment main voltage adjustment value
                bra         .storeReturn

.decVoltageAdj  ldd         mainVoltageAdj      ; load main voltage adjustment
                subd        #$0001              ; decrement it by 1
                bra         .storeReturn        ; and store it back

.LD0FF          ldd         $00CA               ; load 16-bit value from X00CA/CB

.storeReturn    std         mainVoltageAdj      ; store as main voltage adjustment
                rts
code
