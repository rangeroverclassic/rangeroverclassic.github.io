;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       ADC Routine - Diagnostic plug - Channel 14 (8-bit conversion)
;
;   ADC service routines are entered with the newly measured ADC value in
;   X00C8/C9 (only X00C9 for 8-bit readings). The A accumulator also contains
;   the 8-bit reading.
;
;   This routine is used to clear the currently displayed fault to allow the
;   next one to be shown. The fault code area is scanned during boot up and
;   the code is sent to the display using two consecutive calls to a subroutine
;   (each displays 1 digit on the 7-segment display).
;
;   From L-R documentation:
;
;   The following procedure displays the codes, and clears the fault memory:
;   1. Switch On ignition.
;   2. Disconnect serial link mating plug, wait 5 seconds, reconnect.
;   3. Switch OFF ignition, wait for main relay to drop out.
;   4. Switch ON ignition. The display should now reset. If no other faults
;      exist, and the original fault has been rectified, the display will be
;      blank.
;   5. If multiple faults exist repeat Steps 1 to 4. As each fault is cleared
;       the code will change, until all faults are cleared. The display will
;       now be blank.
;
;------------------------------------------------------------------------------
code
adcRoutine14    ldab        $0086
                bitb        #$10            ; test X0086.4 (1 means diag display already updated)
                bne         .LD4BF          ; return if high (already updated)
                
                cmpa        #$80            ; cmpr ADC reading with $80
                ldaa        $00DD           ; bits value (ldaa does not affect carry flag)
                bcc         .LD4C0          ; branch ahead if reading GT $80 (meaning display present)
                
                bita        #$01            ; test 00DD.0
                bne         .LD4DC          ; if bit is set, branch to check for errors
                clr         $202A           ; clear up-counter (used for delay)

.LD4BF          rts                         ; code rtns from here if no display or display already updated
;--------------------------------------------------------------
                                            ; branches here if display is present
.LD4C0          ldab        port1data
                bitb        #$40            ; test P1.6 (fuel pump relay)
                beq         .LD4D5          ; branch ahead if low (fuel pump ON)
                
                ldab        $202A
                incb                        ; increment delay counter
                beq         .LD4D0          ; branch ahead if counter wraps to zero
                
                stab        $202A
                rts                         ; if here, delay is still active, so return
;--------------------------------------------------------------
                                            ; branches here after delay (when counter wraps)
.LD4D0          oraa        #$01
                staa        $00DD           ; set X00DD.0
                rts
;--------------------------------------------------------------
                                            ; code branches here when fuel pump is ON (or from below)
.LD4D5          ldab        $0086
                orab        #$10            ; set X0086.4
                stab        $0086
                rts
;---------------------------------------------------------------
                                                ; branches here if X00DD.0 is high
.LD4DC          clrb
                ldx     #(faultBits_49 - 1)     ; this loop checks for fault bits
                                                ; (scans X0049 thru X004E for non-zero values)
.LD4E0          inx                             ; * Start Loop *
                ldaa        $00,x
                bne         .LD4EC              ; branch ahead if fault found (non-zero)
                incb
                cmpb        #$06
                bne         .LD4E0              ; * End Loop *
                bra         .LD4D5              ; no faults found, branch up, set X0086.4 high and rtn

                                                ; Fault bit found!
.LD4EC          clrb                            ; B used as counter

                                                ; * Start Loop* (right shift to get fault bit into carry)
.LD4ED          incb                            ; increment B
                lsra                            ; shift LSB into carry (LSB is highest priority, code 29 is first)
                bcc         .LD4ED              ; * End Loop *

.LD4F1          asla                            ; * Start Loop * Clear fault bit. (left shift loop to replace the 1 with a 0)
                decb
                bne         .LD4F1              ; * End Loop *
                
                staa        $00,x               ; store it back
                bra         .LD4D5              ; branch to set X0086.4 and return
code
