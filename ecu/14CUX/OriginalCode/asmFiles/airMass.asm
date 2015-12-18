;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       ADC Routine - Air Flow Sensor - Channel 2 (10-bit conversion)
;
;   ADC service routines are entered with the newly measured ADC value in
;   X00C8/C9 (only X00C9 for 8-bit readings). The A accumulator also contains
;   the 8-bit reading from location X00C9.
;
;   This routine simply stores the high and low readings from the air flow
;   sensor. Besides the main MAF signal being handled here, ADC channel 9 can
;   store the MAF trim voltage measurment (open loop only).
;
;------------------------------------------------------------------------------
code
adcRoutine2     ldaa        $0086
                bita        #$02                ; test 0086.1 (this bit is set in ICI)
                bne         .LD23B              ; branch ahead if bit is high (ICI has started)

                                                ; this section records new high or low reading
                ldd         mafDirectHi         ; load previous stored high value
                subd        $00C8               ; subtract new reading
                bcs         .storeHiReading     ; branch to store new higher reading

                                                ; if new reading is lower than high reading
                ldd         mafDirectLo         ; load the 10-bit low air flow reading
                subd        $00C8               ; subtract new reading
                bcs         .return             ; return without saving if new reading is higher

                ldd         $00C8               ; new reading is lower than mafDirectLo
                bra         .saveAndReturn      ; branch to store as new mafDirectLo

.storeHiReading ldd         $00C8               ; new reading is higher
                std         mafDirectHi         ; store new reading as mafDirectHi
                rts                             ; and return

;------------------------------------------------------------------------------
                                                ; this section re-synchronizes the readings
.LD23B          anda        #$FD                ; clr 0086.1
                staa        $0086
                ldd         $00C8
                std         mafDirectHi         ; copy 10-bit value to mafDirectHi

.saveAndReturn  std         mafDirectLo         ; copy 10-bit value to mafDirectLo

.return         rts
code

