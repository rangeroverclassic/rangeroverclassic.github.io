;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       ADC Routine - Tune resistor sense - Channel 10
;
;   ADC service routines are entered with the newly measured ADC value in
;   X00C8/C9 (only X00C9 for 8-bit readings). The A accumulator also contains
;   the 8-bit reading.
;
;   This routine determines which fuel map to use. Maps 0, 4 and 5 are closed
;   loop. Maps 1, 2 and 3 are open loop.
;
;   Starting in the early 90's, USA spec vehicles had the fuel map locked to
;   map 5. This was done by writing data byte $FF to location XC7C1. In this
;   case, there was no need for an external resistor. In fact, the vehicle's
;   wiring harness may be missing the necessary connection to the ECU.
;
;   Bit X0049.7 is the actual fault code (lights MIL if not masked).
;   Bit X2038.2 is the internal 'housekeeping' bit for this fault.
;
;------------------------------------------------------------------------------
code

adcRoutine10    ldab        fuelMapLock             ; load fuel map lock value
                beq         .LD552                  ; branch ahead if zero
                
                ldab        #$05                    ; else...
                stab        fuelMapNumber           ; load 5 as fuel map
                stab        fuelMapNumberBackup     ;
                ldd         #fuelMap5               ; and load the base fuel
                std         fuelMapPtr              ;  map pointer for map 5
                rts                                 ; return
;------------------------------------------------------------------------------
; From Land-Rover Docs:
;
;                    Cat
;  180 Ohms  Red     No    Australia and "the rest of the world."
;  470 Ohms  Green   No    UK and European vehicles without catalytic converters
;  910 Ohms  Yellow  No    Saudi vehicles (without catalytic converters)
; 1800 Ohms  Blue    Yes   Saudi vehicles (with catalytic converters)
; 3900 Ohms  White   Yes   USA and European vehicles with catalytic converters
;
;------------------------------------------------------------------------------
                                                ; if here, lockout value is zero (unlocked)
.LD552          clrb
                cmpa        #$0A                ; ( 4%) less than $0A = map 0
                bcs         .LD571
                incb
                cmpa        #$3D                ; (24%) less than $3D = map 1
                bcs         .LD571
                incb
                cmpa        #$63                ; (39%) less than $63 = map 2
                bcs         .LD571
                incb
                cmpa        #$8D                ; (55%) less than $8D = map 3
                bcs         .LD571
                incb
                cmpa        #$B9                ; (73%) less than $B9 = map 4
                bcs         .LD571
                incb
                cmpa        #$F6                ; (96%) less than $F6 = map 5
                bcs         .LD571
                clrb                            ;    greater than $F6 = map 0
                
;------------------------------------------------------------------------------
; X0085.7 goes to 1 when ignition is turned on and is cleared when engine
; RPM exceeds a minimum value (to indicate that engine is running)
;------------------------------------------------------------------------------                
                                                ; at this point B is the map number (0 through 5)
.LD571          ldaa        $0085               ; X0085.7 indicates no or low eng RPM (eng not running)
                bmi         .LD5B5              ; if set (engine not running) branch to fuel map selector code
                
;------------------------------------------------------------------------------
; Engine is running
;------------------------------------------------------------------------------
                ldaa        $2038               ; if here, engine is running
                bita        #$04                ; test X2038.2 (indicates fuel map resistor fault 21)
                bne         .LD58F              ; branch if fault 21 is already set
                
                ldaa        fuelMapNumber       ; else, compare fuel map number 
                cmpa        fuelMapNumberBackup ; with value saved in battery-backed memory (X0050)
                bne         .LD593
                
                ldaa        $2038               ; if here, fuel map numbers match
                oraa        #$04                ; set X2038.2
                staa        $2038               ;

.LD58B          clr         $203D               ; clear fault 21 delay counter
                rts
;------------------------------------------------------------------------------
; Engine is running (internal fault bit already set)
;------------------------------------------------------------------------------
.LD58F          cmpb        #$00                ; fuel map number equal to zero?
                bne         .LD58B              ; if not, branch up to clr counter and return
;------------------------------------------------------------------------------
; Engine is running (fuel map is zero or fuel map numbers don't agree)
;------------------------------------------------------------------------------
.LD593          ldaa        $203D               ; load fault 21 delay counter
                cmpa        #$FF                ; compare with $FF
                beq         .LD5A6              ; if counter = $FF, branch to set fault bit
                
                inca                            ; increment the counter
                staa        $203D               ; store it
                ldaa        $2038
                bita        #$04                ; test X2038.2 (internal fault bit)
                beq         .LD5B5              ; if zero, branch to Fuel Map Selection
                rts                             ; else, return
;------------------------------------------------------------------------------
; Set Fault Code 21 here (masked out for later NAS tunes)
;------------------------------------------------------------------------------
.LD5A6          ldaa        faultBits_49
                oraa        #$80                ; <-- Set Fault Code 21
                staa        faultBits_49
                ldaa        $2038
                oraa        #$04                ; set X2038.2 internal fault code
                staa        $2038
                rts
;------------------------------------------------------------------------------
; This selects Fuel Map addr ptr based on Fuel Map Number (which is in B accum)
; B accumulator is decremented until zero to find correct pointer.
;------------------------------------------------------------------------------
.LD5B5          stab        fuelMapNumber       ; store fuel map number
                ldab        fuelMapNumber       ; reload it (to set CCR flags)
                beq         .LD5DB
                ldx         #fuelMap1
                decb
                beq         .LD5DE
                ldx         #fuelMap2
                decb
                beq         .LD5DE
                ldx         #fuelMap3
                decb
                beq         .LD5DE
                ldx         #fuelMap4
                decb
                beq         .LD5DE
                ldx         #fuelMap5
                decb
                beq         .LD5DE

.LD5DB          ldx         #fuelMap1

.LD5DE          stx         fuelMapPtr
                rts
;------------------------------------------------------------------------------
code
