;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       ADC Routine - Auto neutral switch - Channel 5 (8-bit conversion)
;
;   ADC service routines are entered with the newly measured ADC value in
;   X00C8/C9 (only X00C9 for 8-bit readings). The A accumulator also contains
;   the 8-bit reading.
;
;   Automatics should read near zero in park and near $FF in drive. Manual
;   gearboxes should read about half count (~$80). Note that the check for
;   fault code 69 is done elsewhere.
;
;
;   From Land Rover Docs:
;
;   The ECM uses this information on transmission gear selection to determine
;   correct positioning of the Idle Air Control (IACV) valve. A diagnostic
;   trouble code (69 [14CUX only]) is set when sensor voltage is 5 V during
;   cranking or 0 V with RPM above 2663 and MAFS voltage above 3V.
;
;------------------------------------------------------------------------------

code
adcRoutine5     staa        neutralSwitchVal    ; this is compared elsewhere with $4D and $B3
                ldab        $0085
                andb        #$02                ; isolate X0085.1
                bne         .LD354              ; branch ahead if X0085.1 is set
                
                ldab        $008A               ; bits value
                cmpa        #$B3                ; compare ADC value with $B3
                bcc         .LD350              ; branch if reading GT $B3 (auto in drive)
                
                                                ; if here, auto in park or manual
                andb        #$CF                ; clr X008A.5 and X008A.4
                orab        #$10                ; set X008A.4
                bra         .LD370              ; store X008A and return

                                                ; if here, auto in drive
.LD350          orab        #$30                ; set X008A.5 and X008A.4
                bra         .LD370              ; store X008A and return

.LD354          ldab        $008A               ; if here, X0085.1 is set
                andb        #$30                ; isolate X008A.5 and X008A.4
                cmpa        #$B3                ; compare ADC value with $B3
                bcc         .LD366              ; branch ahead if >= $B3
                
                cmpb        #$30                ; test X008A.5 and X008A.4
                bne         .LD372              ; return if not zero
                
                ldab        $008A               ; load bits value again
                andb        #$CF                ; clr X008A.5 and X008A.4
                bra         .LD370              ; store X008A and return


.LD366          cmpb        #$10                ; cmpr 008A for xx01 xxxx
                bne         .LD372
                ldab        $008A
                orab        #$20                ; set 008A.5
                andb        #$EF                ; clr 008A.4

.LD370          stab        $008A               ; store X008A

.LD372          rts                             ; return
code
