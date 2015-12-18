;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       This file contains miscellaneous routines.
;
;------------------------------------------------------------------------------

code

;------------------------------------------------------------------------------
; This sets fault bits in 004A or 004D according to the value in A accum
;   $76 = Fault Code 17 (TP sensor)
;   $70 = Fault Code 14 (ECT sensor)
;   $71 = Fault Code 15 (EFT sensor)
;   $01 = Fault Code 18 (TP GT $0332 or 4.0 volts under certain conditions)
;------------------------------------------------------------------------------

IF BUILD_R3360_AND_LATER
;---------------------------------------------------------------------------------
setTempTPFaults psha
                ldd         faultSlowDownCount
                beq         .okToSetFaults
                addd        #$0001
                std         faultSlowDownCount
                pula
                rts
                
.okToSetFaults  pula
                cmpa        #$76
                beq         .setTPFault17
                cmpa        $C0CD               ; data value is $70
                beq         .setCTFault14
                cmpa        #$71
                beq         .setFTFault15
                cmpa        #$01
                beq         .setTPFault18
                rts
;---------------------------------------------------------------------------------
ELSE    ; Griffith
;---------------------------------------------------------------------------------
setTempTPFaults	ldab	    $00D1
			    beq		    .okToSetFaults
			    incb
			    stab	    $00D1
			    rts

.okToSetFaults  cmpa	    #$76
		        beq		    .setTPFault17
		        cmpa	    $C0CD	            ; data value is $70
                beq         .setCTFault14
		        cmpa	    #$FF
		        beq		    .setMafFaultFF		; MAF fault (replaced by DTC 12)
		        cmpa	    #$71
                beq         .setFTFault15
		        cmpa	    #$01
                beq         .setTPFault18
		        cmpa	    #$02
		        beq		    .setTPFault19		; branch to TP Fault Code 19
		        rts
;---------------------------------------------------------------------------------
ENDC                


.setTPFault17   ldab        faultBits_4A
                orab        #$10                ; Set TP Sensor Fault Code 17
                stab        faultBits_4A
                rts

.setCTFault14   ldab        faultBits_4A
                orab        #$08                ; Set ECT Sensor Fault Code 14
                stab        faultBits_4A
                rts
                
IF BUILD_R3360_AND_LATER
                ; nothing
ELSE

.setMafFaultFF	ldab	    $0049
			    orab	    #$40		        ; set MAF fault bit
			    stab	    $0049
			    ldab	    $0087
			    orab	    #$02		        ; set MAF fault bit
			    stab	    $0087
			    rts
ENDC


.setFTFault15   ldab        faultBits_4D
                orab        #$20                ; Set EFT Sensor Fault Code 15
                stab        faultBits_4D
                rts

.setTPFault18   ldab        faultBits_4A
                orab        #$20                ; Set TP Sensor Fault Code 18
                stab        faultBits_4A
                rts

IF BUILD_R3360_AND_LATER
                ; nothing
ELSE

.setTPFault19	ldab	    $004A		        ; value 02 (fault code 19?)
			    orab	    #$40		        ; removed from R3526 code
			    stab	    $004A
			    rts
ENDC

;---------------------------------------------------------------------------------
;                          Stepper Motor Subroutine
;
; This is called from both a main loop subroutine and the throttle pot routine.
;---------------------------------------------------------------------------------

LEE12           ldab        iacMotorStepCount   ; absolute value of stepper mtr adjustment
                bne         .LEE28              ; return if iacMotorStepCount is not zero
                
                ldab        $0073               ; 
                beq         .LEE28              ; return if X0073 is zero
                
                stab        iacMotorStepCount   ; store X0073 as iacMotorStepCount
                ldab        $008A
                orab        #$01                ; set X008A.0 (stepper mtr direction, 1 = close)
                stab        $008A
                clr         $0073               ; and clr 0073
                inc         $00B3               ; idle speed adjustment

.LEE28          rts

;------------------------------------------------------------------------------
; This is called from two places in a subroutine One with X = X008E and the
; other with X = X0090.
; The routine adds or subtracts 0001 to/from X008E/8F or X0090/91
;
;------------------------------------------------------------------------------
LEE29           ldd         $00,x
                beq         .LEE39              ; return if indexed double value is zero
                bmi         .LEE34
                subd        #$0001              ; subtract 1 if value is positive
                bra         .LEE37

.LEE34          addd        #$0001              ; add 1 if value is negative
.LEE37          std         $00,x
.LEE39          rts
;------------------------------------------------------------------------------

code

