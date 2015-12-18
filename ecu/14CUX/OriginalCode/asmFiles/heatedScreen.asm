;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       ADC Routine - Heated screen sense - Channel 1 (8-bit conversion)
;
;   ADC service routines are entered with the newly measured ADC value in
;   X00C8/C9 (only X00C9 for 8-bit readings). The A accumulator also contains
;   the 8-bit reading.
;
;   LOW AT THE ADC MEANS HEATER IS ON.

;   Low  at ADC is ON   (less than $80)
;   High at ADC is OFF  (greater than $7F)
;    
;------------------------------------------------------------------------------
code

adcRoutine1     ldab        $0085               ; X0085.1 may indicate extra engine load
                andb        #$02                ; isolate X0085.1
                bne         .LD50E              ; branch ahead if X0085.1 is set
                
                ldab        $00DD               ; if here, eng load bit is zero
                tsta                            ; A accum is 8-bit ADC reading
                bmi         .LD50A              ; branch ahead if ADC reading > $7F
;-----------------------------------------------------------
; Screen Heater is ON    (X0085.1 was 0)
;-----------------------------------------------------------
                andb        #$F9                ; clear the 2 bits
                orab        #$02                ; set X00DD to xxxx x01x
                bra         .LD529              ; branch to store X00DD and rtn
;-----------------------------------------------------------
; Screen Heater is OFF   (X0085.1 was 0)
;-----------------------------------------------------------
                                                ; ADC reading is < $80 (heater ON)
.LD50A          orab        #$06                ; set X00DD to xxxx x11x
                bra         .LD529              ; store X00DD and return
;-----------------------------------------------------------
; X0085.1 is 1
;-----------------------------------------------------------
                                                ; code branches here if X0085.1 is set (extra eng load)
.LD50E          ldab        $00DD
                andb        #$06                ; isolate bits 00DD.2 and 00DD.1
                tsta                            ; A accum is 8-bit ADC reading
                bmi         .LD51F              ; branch ahead if ADC reading is high (heater OFF)
;-----------------------------------------------------------
; Screen Heater is ON    (X0085.1 was 1)
;-----------------------------------------------------------
                cmpb        #$06                ; <-- heater is ON
                bne         .LD52B              ; rtn if not xxxxx11x
                ldab        $00DD
                andb        #$F9                ; set X00DD to xxxx x00x
                bra         .LD529              ; branch to store and return
;-----------------------------------------------------------
; Screen Heater is OFF   (X0085.1 was 1)
;-----------------------------------------------------------
                                                ; <-- heater is OFF
.LD51F          cmpb        #$02                ; test for xxxx x01x
                bne         .LD52B              ; rtn if not equal
                ldab        $00DD
                orab        #$04
                andb        #$FD                ; set X00DD to xxxx x10x

.LD529          stab        $00DD               ; store X00DD

.LD52B          rts

code
