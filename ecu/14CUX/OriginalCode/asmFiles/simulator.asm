;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:    Simulator Code
;
;   This module is optionally added to the 14CUX code by turning on the
;   SIMULATION_MODE bit. In addition to adding this code, the SIMULATION_MODE
;   does the following:
;
;   1) Deletes the copying of 19 bytes of memory from the battery-backed area
;       to external RAM locations $2060 through $2072. Other code which checks
;       and updates this external memory is also deleted. This RAM area is then
;       free for use by the simulator.
;
;   2) The RAM area ($2060-$2072) can now be written with prepared simulation
;       values, prior to turning simulation mode On. This is done through the
;       normal serial port interface using the write command.
;
;   3) Simulation mode is turned ON by writing $55 to location $2072.
;
;   4) When simulation mode is active, the 'simulation' subroutine (below) is
;       immediatley called right after the main loop ADC measurment is made.
;       This replaces the actual measured value with one from the RAM area.
;
;   5) In addition, 4 other ADC measurements are be made from the ICI. Here is 
;       how they are handled:
;               TPS Measurement -- uses in-line simulation code
;               MAF Measurement -- uses in-line simulation code
;               HO2 Measurement -- both L & R call 'o2Simulation' below
;
;   In combination with 2 function generators, this allows full simulation
;   of any scenario.
;
;   One function generator is needed to simulate the engine spark. This needs
;   to be a pulse generator with a greater than TTL output and probably an
;   external booster transformer.
;
;   The second function generator is for the road speed (VSS) input signal to
;   the ECU. A 12 volt square wave is ideal, although a 7 Volt waveform should
;   work. TTL level will work if the threshold in the software is lowered.
;   
;   This describes use of the simulation RAM area. All values are 8-bit unless
;   otherwise noted.
;
;   $2060    = inertia switch
;   $2061    = heated screen
;   $2062/63 = air flow (10 bits)
;   $2064/65 = throttle pot (10 bits)
;   $2066    = coolant temp
;   $2067    = neutral switch
;   $2068    = air cond load
;   $2069    = road speed
;   $206A    = main relay
;   $206B    = air idle trim
;   $206C    = tune resistor
;   $206D    = fuel temp
;   $206E    = left O2
;   $206F    = O2 reference
;   $2070    = diag plug
;   $2071    = right O2
;   $2072    = control word (00 = OFF, 55 = ON)
;
;
;   Simulator Timeline:
;       Toggling 4004.4 to frame ICI = 10 + 10 = 20 clocks
;       Code block that toggles 4004.7 = 21 or 24 clocks
;       Main loop call to simulator2 = 41 to 59 clocks
;       Code Block 9000 = 127 clocks
;
;       Skipping the 4004.7 code will balance the 4004.4 toggle.
;       Skipping the 9000 code will balance 2 to 3 main loop ADC calls.
;
;------------------------------------------------------------------------------

code

;------------------------------------------------------------------------------
;                       Main Simulation Routine
;
;   If code was built with SIMULATION_MODE turned on (non-zero), this routine
;   is called immediately after the main loop ADC measurement is made.
;
;   Coming in to this routine, B accumulator is the ADC channel number (0 - F),
;   and X (index register) is #adcVectors location. Both of these registers
;   need to be preserved. The A accumulator does not need to be preserved.
;
;   "simulation2" is an attempt to balance the clock cycles for more even
;   loading so that compensation elsewhere is more effective.
;
;   Clock cycles:   add [6] for jsr (extended)
;
;   MAF: 9 + 5 + 5 + 3 + 19 + 6 = 41
;   TPS: 9 + 5 + 5 + 3 + 19 + 6 = 41
;   < 2: 9 + 5     + 34     + 6 = 54
;   > 3: 9 + 5 + 5 + 34     + 6 = 59
;
;------------------------------------------------------------------------------
simulation2     ldaa        $2072           ; [4] check the value that turns sim on/off
                cmpa        #$55            ; [2] $55 turns it on
                bne         .return         ; [3] return if not $55

                cmpb        #$02            ; [2]
                bcs         .lessThan2      ; [3] branch if channel 0 or 1

                cmpb        #$03            ; [2] 
                bcc         .greaterThan3   ; [3] branch if channel 3 or greater

                beq         .throttlePot    ; [3] branch if channel 3

;---------------------------------------
                                            ;     fall through to channel 2
.airFlow        ldaa        $2063           ; [4] MAF so use 2-byte value at $2063/64
                staa        $00C9           ; [3]
                ldaa        $2062           ; [4]
                staa        $00C8           ; [3]
                rts                         ; [5]

;---------------------------------------

.lessThan2      pshx                        ; [4] channel is zero or 1
                ldx         #$2060          ; [5] use $2060 or $2061
                abx                         ; [3]
                ldaa        $00,x           ; [4]
                staa        $00C9           ; [3]                
                clra                        ; [2]
                staa        $00C8           ; [3]
                pulx                        ; [5]
                rts                         ; [5]

;---------------------------------------

.greaterThan3   pshx                        ; [4] channel is > 3 so memory location
                ldx         #$2062          ; [5] is offset by 2 additional bytes
                abx                         ; [3]
                ldaa        $00,x           ; [4]
                staa        $00C9           ; [3]
                clra                        ; [2]
                staa        $00C8           ; [3]
                pulx                        ; [5]
                rts                         ; [5]

;---------------------------------------


.throttlePot    ldaa        $2065           ; [4] TPS so use 2-byte value at $2065/66
                staa        $00C9           ; [3]
                ldaa        $2064           ; [4]
                staa        $00C8           ; [3]

.return         rts                         ; [5]

;------------------------------------------------------------------------------

code




code
;------------------------------------------------------------------------------
;                       Main Simulation Routine
;
;   If code was built with SIMULATION_MODE turned on (non-zero), this routine
;   is called immediately after the main loop ADC measurement is made.
;
;   Coming in to this routine, B accumulator is the ADC channel number (0 - F),
;   and X (index register) is #adcVectors location. Both of these registers
;   need to be preserved. The A accumulator does not need to be preserved.
;
;   Clock cycles:   add [6] for jsr (extended)
;
;   MAF: 9 + 5 + 19         + 6 = 39
;   TPS: 9 + 5 + 5 + 19     + 6 = 44
;   < 2: 9 + 5 + 5 + 3 + 35 + 6 = 63
;   > 3: 9 + 5 + 5 + 3 + 35 + 6 = 63
;
;------------------------------------------------------------------------------
simulation      ldaa        $2072           ; [4] check the value that turns sim on/off
                cmpa        #$55            ; [2] $55 turns it on
                bne         .return         ; [3] return if not $55


                cmpb        #$02            ; [2] channel 2 is MAF
                beq         .airFlow        ; [3]

                cmpb        #$03            ; [2] channel 3 is throttle pot
                beq         .throttlePot    ; [3]

                bcc         .greaterThan3   ; [3] branch if channel > 3

;---------------------------------------

.lessThan2      pshx                        ; [4] channel is zero or 1
                ldx         #$2060          ; [5] use $2060 or $2061
                abx                         ; [3]
                ldaa        $00,x           ; [4]
                staa        $00C9           ; [3]
                clr         $00C8           ; [6] (extended, no direct available)
                pulx                        ; [5]
                rts                         ; [5]

;---------------------------------------

.greaterThan3   pshx                        ; [4] channel is > 3 so memory location
                ldx         #$2062          ; [5] is offset by 2 additional bytes
                abx                         ; [3]
                ldaa        $00,x           ; [4]
                staa        $00C9           ; [3]
                clr         $00C8           ; [6] (extended, no direct available)
                pulx                        ; [5]
                rts                         ; [5]

;---------------------------------------

.airFlow        ldaa        $2063           ; [4] MAF so use 2-byte value at $2063/64
                staa        $00C9           ; [3]
                ldaa        $2062           ; [4]
                staa        $00C8           ; [3]
                rts                         ; [5]

;---------------------------------------

.throttlePot    ldaa        $2065           ; [4] TPS so use 2-byte value at $2065/66
                staa        $00C9           ; [3]
                ldaa        $2064           ; [4]
                staa        $00C8           ; [3]

.return         rts                         ; [5]

;------------------------------------------------------------------------------




;------------------------------------------------------------------------------
;   Simulation code for O2 sensors
;
;   This routine uses memory locations $00A2 (left) and $00A3 (right) which
;   are otherwise unused in the standard code build.
;
;   The 8-bit value needs to be higher than the O2 reference to be recognized
;   as a high and lower then the reference to be low. It may be OK to just use
;   values $00 and $FF. Return the value in the B accumulator register.
;
;   currently doing a toggle (50%)
;
;   
;
;------------------------------------------------------------------------------
o2Simulation    ldab        $2072           ; [4]
                cmpb        #$55            ; [2]
                bne         .return         ; [3]
                
                tst         $0088           ; [6] which bank? (0 = left, 1 = right)
                bpl         .left           ; [3] branch if left
                
.right          ldaa        $00A2           ; [3] <-- Right Bank
                eora        #$80            ; [2] toggle bit 7
                staa        $00A2           ; [3]
                bpl         .low            ; [3]
                
.high           ldab        #$FF            ; [2]
                rts                         ; [5]
                
.low            clrb                        ; [2]
                rts                         ; [5]
                
.left           ldaa        $00A3           ; [3] <-- Left Bank
                eora        #$80            ; [2] toggle bit 7
                staa        $00A3           ; [3]
                bpl        .low             ; [3]
                bra        .high            ; [3]
                
;------------------------------------------------------------------------------

code
