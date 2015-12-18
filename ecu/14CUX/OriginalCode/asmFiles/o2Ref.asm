;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       ADC Routine - O2 reference - Channel 13 (8-bit conversion)
;
;   ADC service routines are entered with the newly measured ADC value in
;   X00C8/C9 (only X00C9 for 8-bit readings). The A accumulator also contains
;   the 8-bit reading.
;
;   This channel appears to be reading a slightly raised ground voltage. This
;   reading is quite low (20 to 25 decimal) but is used as a compare value
;   for the HO2 sensor readings (also fairly low). This is probably reading
;   the heater return line which will have a small voltage due to the flow
;   of heater current. The value is simply stored for later use in the spark
;   interrupt (closed loop only).
;
;------------------------------------------------------------------------------

adcRoutine13    staa        o2ReferenceSense
                rts

