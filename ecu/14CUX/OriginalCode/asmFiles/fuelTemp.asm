;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       ADC Routine - Fuel Temp Thermistor - Channel 11 (8-bit conversion)
;
;   ADC service routines are entered with the newly measured ADC value in
;   X00C8/C9 (only X00C9 for 8-bit readings). The A accumulator also contains
;   the 8-bit reading.
;
;   Note that for both HO2 sensors the ADC service routine table points to
;   the 'rts' (return from subroutine) at the end of this routine.
;
;
;    From Land Rover Docs:
;
;    Engine Fuel Temperature Sensor (EFTS)
;    The fuel temperature sensor, mounted on the fuel rail, operates in the
;    same manner as the ECTS. When the ECM receives a high fuel temperature
;    input, it increases injector pulse during hot restarts. When fuel is hot,
;    vaporization occurs in the fuel rail and bubbles may be found in the
;    injectors. This can lead to hard starting. Increasing injector pulse time
;    flushes the bubbles away and cools the fuel rail with fresh fuel from the
;    tank. Since 1989, the EFTS has also been used by ECM to trigger operation
;    of the radiator fans when under-hood temperatures become extreme.
;    As with the engine coolant temperature sensor, a diagnostic trouble code
;    (15 [14CUX only]) is stored when the signal is out of range (0.08V to 4.9V)
;    for longer than 160 milliseconds. No default value is provided by the ECM,
;    however the MIL will illuminate.
;
;   Note about sensor limits.
;   When checking the range of the EFT counts, the addition of $04 
;   checks for exceeded limits at both ends of the sensor. For example,
;   adding $04 and checking for a minimum of $08 checks for a low count
;   minimum of $04 but it also checks for a high count maximum of $FC which
;   is -4 in two's complement, since the value would wrap and look like a
;   small positive number.
;
;------------------------------------------------------------------------------

code
adcRoutine11    staa        fuelTempCount       ; EFT sensor count
                tab                             ; xfr it to B accum
                addb        #$04                ; add 4 (see note about sensot limits above)
                cmpb        #$08                ; compare it to 8
                bhi         .LD457              ; branch if value is > 8 (EFT reading is OK)

                ldaa        #$71                ; $71 is code for fuel temp sensor fault (also default val)
                jsr         setTempTPFaults     ; <-- Set Fault Code 15 (Fuel Temp)


.LD457          ldab        $0085               ; X0085.4 is cleared after mux list finishes at least once)
                bitb        #$10                ; test X0085.4
                beq         .LD468              ; branch ahead if X0085.4 is clr
                suba        hiFuelTemperature   ; this is the temp saved in battery backed memory
                bcs         .LD487              ; branch ahead if fuel temp is < hiFuelTemperature
;-----------------------------------------------------------
                                                ; fall through or branch up from 1 place below
.LD461          ldaa        $008A               ; gets here normally when saved hot EFT is zero
                oraa        #$02                ; set X008A.1 (this is the only place this bit is set)
                staa        $008A               ; store it

.LD467          rts                             ; return
;-----------------------------------------------------------
                                                ; branches here if X0085.4 is clr
.LD468          ldaa        $008A
                bita        #$02                ; test X008A.1
                bne         .LD467              ; return if bit is 1
                
                bitb        #$20                ; test X0085.5
                beq         .LD467              ; rtn if bit is zero
                
                ldaa        $00A1               ; X00A1 down-counter (only used in this routine)
                beq         .LD47A              ; branch ahead if down-counter is zero
                
                dec         $00A1               ; else decrement it and return
                rts
;-----------------------------------------------------------
.LD47A          ldaa        $C0AE               ; for R3526, value is $02
                staa        $00A1               ; store it at X00A1
                ldx         $009F               ; value at X009F/A0 is only written in this routine
                beq         .LD461              ; branch up if zero
                dex                             ; decrement X009F/A0
                stx         $009F               ; store it
                rts                             ; and return
;-----------------------------------------------------------
                                                ; code gets here if fuel temp is hotter than saved hot fuel temp
.LD487          nega                            ; convert negative temp delta to positive
                ldab        $C0AF               ; for R3526, value is $32 (48 dec)
                mul                             ; 48 * temp_delta
                std         $009F               ; store the 16-bit result
                subd        $C0B2               ; for R3526, value is $0780 (1920 dec)
                bcs         .LD498              ; branch if calculated value < $0780 
                
                ldd         $C0B2               ; else store $0780 (this sets a limit)
                std         $009F               ;


.LD498          ldaa        $C0AE               ; for R3526, value is $02
                staa        $00A1               ; store it in X00A1
                                                ; fall through to rts below
;------------------------------------------------------------------------------
;    ADC Routine - O2 Sensors - Channels 12 and 15
;    The O2 sensors are tested in the main code loop
;------------------------------------------------------------------------------

o2sense         rts
code
