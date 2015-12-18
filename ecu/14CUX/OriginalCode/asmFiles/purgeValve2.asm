;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:    Purge Valve Timer Subroutine
;
;   This is called from 2 places in the ICI if purgeValveTimer is not zero.
;   The AB regs are loaded with purgeValveTimer before calling and there
;   is a bcs after each return.
;
;   It seems when X00E2.4 is set, purge valve is turned OFF by interrupt.
;
;------------------------------------------------------------------------------

code

purgeValveBits  ldaa        $00E2               ; load bits value
                bita        #$01                ; test X00E2.0
                bne         setCarry            ; set carry and return
                
                tst         $0088               ; test X0088.7 (bank indicator bit)
                bmi         .leftBank           ; if set, left bank
                
;-----------------------
; Right bank code
;-----------------------
                bita        #$04                ; test X00E2.2
                bne         clearCarry          ; if 1, clr carry and return
                
                ldab        $00D4               ; right bank counter
                incb                            ; increment it
                bne         .LF3F1              ; branch if it hasn't wrapped to zero
                
                bita        #$02                ; test X00E2.1
                bne         .LF3EB              ; branch if bit is set
                
                oraa        #$12                ; set X00E2.4 and X00E2.1
.LF3E7          staa        $00E2               ; store it
                bra         .LF3F1              ; branch ahead

.LF3EB          oraa        #$04                ; set X00E2.2
                anda        #$ED                ; clr X00E2.4 and X00E2.1
                bra         .LF3E7              ; branch back

.LF3F1          stab        $00D4               ; store X00D4
                sec                             ; set carry flag
                rts                             ; return
                
;-----------------------
; Left bank code
;-----------------------
.leftBank       bita        #$40                ; test X00E2.6
                bne         clearCarry          ; if 1, clr carry and return
                
                ldab        $00D5               ; left bank counter
                incb                            ; increment it
                bne         .LF40E              ; branch if it hasn't wrapped to zero
                
                bita        #$20                ; test X00E2.5
                bne         .LF408              ; branch if bit is set
                
                oraa        #$30                ; set X00E2.5 and X00E2.4
.LF404          staa        $00E2               ; store it
                bra         .LF40E              ; branch ahead

.LF408          oraa        #$40                ; set X00E2.6
                anda        #$CF                ; clr X00E2.5 and X00E2.4
                bra         .LF404              ; branch back

.LF40E          stab        $00D5               ; store X00D5
                sec                             ; set carry flag
                rts                             ; return
;-----------------------
; Clear carry and return
;-----------------------
clearCarry      clc
                rts
;-----------------------
; Set carry and return
;-----------------------
setCarry        sec
                rts
code
