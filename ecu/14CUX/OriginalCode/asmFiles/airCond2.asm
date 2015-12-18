;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       The A/C service routine can jump to this code block which is in a
;   different location, outside of the branch range. There is no apparent
;   reason why it was separated.
;
;   Value (either $00 or $FF) is passed in A accumulator.
;       If A is $00, X008C.7 is cleared.
;       If A is $FF, X008C.7 is set.
;
;------------------------------------------------------------------------------

code
LD49E           ldab        $008C               ; X008C is a bits value
                tsta                            ; test bit 7 (pos or neg)
                bmi         .LD4A7              ; branch if minus (bit is set)
                andb        #$7F                ; clr 008C.7
                bra         .LD4A9


.LD4A7          orab        #$80                ; set 008C.7


.LD4A9          stab        $008C               ; store value
                rts                             ;   and return to main loop
code
