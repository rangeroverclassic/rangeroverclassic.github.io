;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:    Purge Valve Interrupt
;
;   This is Output Compare Interrupt 2 (OCF2 Interrupt) for the 6803U4.
;
;   H02S = Heated Oxygen Sensor
;   This interrupt is triggered when the Output Compare Register 2 (OCR2)
;   matches the free running clock. It seems when X00E2.4 is set, purge valve
;   is turned OFF by interrupt. The actual value is 1720 not 1700 RPM.
;
;   Besides this interrupt, there are two subroutines having to do with the
;   purge valve. One is called from the ECT subroutine. The other is called
;   from two places in the ICI.
;
;   Note that even though the microprocessor's non-maskable interrupt (NMI)
;   is not used, the NMI vector points to the 'rti' instruction at the end
;   of this routine (simply for good coding practice).
;
;   From Land Rover Docs:
;
;   The ECM pulses the valve open for short periods below 1700 RPM and holds
;   it open at higher speeds once the engine has achieved operating temperature
;   and is in closed loop. Operating temperature is defined as engine coolant
;   temperature above 54 C (130 F).
;
;   The ECM monitors the need for canister purge by looking at HO2S response
;   when the valve is opened. No change in HO2S response with the valve open
;   indicates that the canister has been purged of fuel vapor and continued
;   valve operation is no longer necessary. Operation of the purge function
;   when no longer required can negatively impact vehicle emissions.
;
;------------------------------------------------------------------------------

code

purgeValveInt   ldaa        timerCSR            ; OCF2 flag is reset by reading one of these two
                ldaa        timerStsReg         ;  locations and then writing to ocr2 high or low
                ldaa        $00E2
                bita        #$10                ; test X00E2.4
                bne         .LDB24              ; branch ahead if bit is set
                
                ldd         purgeValveTimer     ; load purge valve timer value
                subd        #$0FA0              ; subtract 4000 dec
                bcs         .LDB24              ; branch to .LDB24 if value < 4000 dec
                
                subd        #$61A8              ; subtract 25,000 dec
                bcc         .LDB2E              ; branch to .LDB2E if value > 29,000

                ldaa        port1data
                eora        #$02                ; toggle P1.1 (purge control valve)
                staa        port1data
                bita        #$02                ; and test it
                bne         .LDB34              ; branch to .LDB34 if bit is now set

                ldd         ocr2high            ; <-- bit is low, purge valve turns ON (timer is between 4K and 29K)
                addd        purgeValveTimer     ; (for between 4 and 29 ms)
                std         ocr2high
                rti

.LDB24          ldaa        port1data           ; if here, X00E2.4 is set OR X0096 is < 4000
                oraa        #$02                ; set P1.1 to turn purge valve OFF

.LDB28          staa        port1data
                ldd         ocr2high            ; just read ocr2 so we can write it back and clear the flag
                bra         .LDB3B              ; branch down to write it back to register and rti
                                                
.LDB2E          ldaa        port1data           ; if here, purgeValveTimer > 29,000
                anda        #$FD                ; clear P1.1 to turn it ON
                bra         .LDB28
                                                ; if here, bit is high, purge valve turns OFF
.LDB34          ldd         ocr2high            ; purgeValveTimer is between 4K and 29K
                addd        #$7A12              ; 31250 dec (stay off for 31 minus ? ms)
                subd        purgeValveTimer     ; subtract purge valve timer value

.LDB3B          std         ocr2high            ; write to 16-bit MPU register
;------------------------------------------------------------------------------
; NMI and IRQ1 interrupts are not used
;------------------------------------------------------------------------------

nmiInterrupt    rti                             ; return from interrupt

code
