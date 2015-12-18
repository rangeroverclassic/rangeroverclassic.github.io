;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       Fault code related data and routines.
;
;   This code may be either a late change or NAS specific and may not appear
;   in TVR code.
;
;------------------------------------------------------------------------------
code

IF BUILD_R3360_AND_LATER
;------------------------------------------------------------------------------
; These 6 mask bytes are applied to the six fault bit locations (X0049 to 4E)
; Here, some faults can be prevented from lighting the MIL. For example, bit 7
; in X0049 is the tune resistor fault. The value $77 masks this fault for
; tunes that are locked to map 5.
;------------------------------------------------------------------------------

.faultMasks     DB          $77, $FD, $00, $D0, $20, $C0

ENDC

;------------------------------------------------------------------------------
;                            *** Fault Code Scan ***
; This subroutine is called once from the reset routine at startup. It scans
; the 6 fault bit locations looking for the first set bit (these are in memory
; in prioritized order). The math is then done to get the fault code from the
; table below. The code is then stored temporarily at the same location used
; for the right short-term lambda trim (X0067).
;------------------------------------------------------------------------------
faultCodeScan   clrb

IF BUILD_R3360_AND_LATER
                                                    ; this is the later L-R version
.faultScanLoop      ldx         #faultBits_49       ; 
                    abx                             ; add B (offset) to X
                    ldaa        $00,x               ; load indexed fault byte
                    ldx         #.faultMasks        ; load address of fault masks
                    abx                             ; add B (offset) to X
                    anda        $00,x               ; AND fault code with mask value
                    bne         .foundFaultBit      ; branch ahead if not zero
                    incb                            ; increment B
                    cmpb        #$06                ; compare with 6
                    bne         .faultScanLoop      ; loop back if less than 6
                    bra         .storeFaultRet      ; branch to store zero (no fault)
                
ELSE
                                                    ; this is the TVR version (before mask values)
			        ldx	        #$0048       
.faultScanLoop      inx
			        ldaa	    $00,x
	    		    bne	        .foundFaultBit
		            incb
			        cmpb	    #$06
			        bne	        .faultScanLoop
			        bra	        .storeFaultRet
ENDC                
                

.foundFaultBit      pshb                            ; B is index counter (0 thru 5)
                    tab                             ; transfer A to B (fault code)
                    clra                            ; clr A

                                                    ; start loop (A is zero, B is fault code)
.isolateFaultBit    lsrb                            ; logic shift right
                    bcs         .faultCodeFromBit   ; branch out if carry set (1 was shifted out)
                    inca                            ; increment A
                    bne         .isolateFaultBit    ; should only loop a max of 7 times

.faultCodeFromBit   staa        tmpFaultCodeStorage ; this is the bit number of the set bit
                    pulb                            ; B is index counter (0 thru 5)
                    ldaa        #$08                ; 8 bits per byte
                    mul                             ; mpy to get to 8-bit segment
                    addb        tmpFaultCodeStorage ; 
                    ldx         #.faultCodes        ; address of fault code table (below)
                    abx                             ; add B to index
                    ldaa        $00,x               ; get value from table

.storeFaultRet      staa        tmpFaultCodeStorage
                    rts

;------------------------------------------------------------------------------
;   The fault code table is shown here in numerical order
;------------------------------------------------------------------------------
; 02 03 11 12 14 15 16 17
; 18 19 21 22 23 25 26 27
; 28 29 34 35 36 37 38 39
; 40 40 44 45 46 47 48 49
; 50 50 55 56 57 58 59 66
; 67 68 69 77 78 79 88 89
;------------------------------------------------------------------------------
;   The table is shown here in priorized order (as it exists in memory)
;------------------------------------------------------------------------------
;                            byte mask
; 29 44 45 25 40 50 12 21  ; 0049 (77) ECM, O2A, O2B, MisfireA, MisfireB, MAF (25, 21 not used)
; 34 35 36 14 17 18 19 88  ; 004A (FD) Inj-A, Inj-B, CTS, TPS, TPS, TPS, purge (35 not used)
; 89 26 27 28 37 38 39 22  ; 004B (00) (none used)
; 23 49 46 47 48 11 68 69  ; 004C (D0) Idle Valve, VSS, Neutral Switch (23,49,46,47,11 not used)
; 55 56 57 58 59 15 16 66  ; 004D (20) Fuel Temp (15), all others unused
; 67 77 78 79 40 50 02 03  ; 004E (C0) 02 & 03 only used
;------------------------------------------------------------------------------
; An interesting point:
; This data table is in BCD (binary coded decimal) so there is no difference
; between the decimal and hex representations.
;------------------------------------------------------------------------------

.faultCodes     DB          $29, $44, $45, $25, $40, $50, $12, $21
                DB          $34, $35, $36, $14, $17, $18, $19, $88
                DB          $89, $26, $27, $28, $37, $38, $39, $22
                DB          $23, $49, $46, $47, $48, $11, $68, $69
                DB          $55, $56, $57, $58, $59, $15, $16, $66
                DB          $67, $77, $78, $79, $40, $50, $02, $03

;------------------------------------------------------------------------------
; This routine can be called from the ICI to set the O2 Sensor Fault
;------------------------------------------------------------------------------

LF3A3           ldab        $00D3
                tst         $0088               ; test bank indicator bit
                bmi         .LF3B5              ; branch ahead if bit is 1 (right bank)                
;---------------------------------------
; Left Bank
;---------------------------------------
                ldaa        faultBits_49        ; 
                oraa        #$02                ; <-- Set Fault Code 44 (O2 Sensor A Fault, left bank)
                staa        faultBits_49        ; 
                orab        #$01                ; set X00D3.0 to indicate Sensor A fault
                stab        $00D3               ; 
                rts
;---------------------------------------
; Right Bank
;---------------------------------------
.LF3B5          ldaa        faultBits_49        ; 
                oraa        #$04                ; <-- Set Fault Code 45 (O2 Sensor B Fault, right bank)
                staa        faultBits_49        ; 
                orab        #$02                ; set X00D3.1 to indicate Sensor B fault
                stab        $00D3               ; 
                rts
                
;------------------------------------------------------------------------------
; This routine can be called from 2 places in ICI.
; It clrs some bank related values.
;------------------------------------------------------------------------------
LF3C0           clra
                tab
                std         $008E
                std         $0090
                std         $0094
                std         $00A9
                std         $00AB
                rts

code
