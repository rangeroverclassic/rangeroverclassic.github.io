;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       ADC Routine - A/C load input - Channel 6 (8-bit conversion)
;
;   ADC service routines are entered with the newly measured ADC value in
;   X00C8/C9 (only X00C9 for 8-bit readings). The A accumulator also contains
;   the 8-bit reading.
;
;   On start-up, bit X205B.4 is set and 'startupDownCount1Hz' is set to 12.
;   It is then decremented to zero at approximately 1 Hz rate.
;
;   LOW AT THE ADC MEANS A/C IS OFF.
;
;   205B.3  Only used in this routine (set when ECT > 226 F, cleared when ECT < 221 F)
;   205B.4  Only used in this routine (set when engine starts)
;   2059.1  Only used in this routine 
;   205A    Only used in this routine (up-counter)
;   2039    ! Hz down-counter (decremented by road speed comparator routine)
;    
;   These are the outputs of this routine:
;   008A.3  Main loop A/C compressor control
;               (1 = A/C OFF, clear P2.2)
;               (0 = A/C ON,    set P2.2)
;   008C.7  ICI A/C compressor control       
;               (0 = A/C OFF, clear P2.2)
;               (1 = A/C ON,    set P2.2)
;
;   Note that the first version in this file is the later LR version and the
;   second version at the bottom of the file is the version found in Griffith
;   code. The later LR version uses new data values XC7DD, XC7DE and XC7DF.
;
;------------------------------------------------------------------------------

code

IF NEW_STYLE_AC_CODE

adcRoutine6     psha                            ; push the air cond load reading
                ldab        $205B
                bitb        #$10                ; test 205B.4 (engine started flag)
                beq         .LD263              ; branch ahead if engine started flag is zero
;-----------------------------------------------------------
;  This block executed only after engine start
;-----------------------------------------------------------
                ldd         ignPeriodFiltered
                subd        #$FFFF              ; this subtracts the init value
                bne         .LD277              ; branch ahead if not init value (eng cranking or started)

                clrb                            ; eng was started, so what happened to get here?
                stab        startupDownCount1Hz ; reset 1 Hz startup down-counter to zero
                ldab        $205B
                andb        #$EF                ; clr 205B.4 (clr eng started flag)
                stab        $205B
                bra         .LD277
;-----------------------------------------------------------
;        Engine started flag not set
;        
;  Check filtered ign period for 500 RPM (375 for CWC)
;-----------------------------------------------------------
                                                ; 1-time code at startup
.LD263          ldab        ignPeriodFiltered
                cmpb        #ignPeriodEngStart  ; usually 500 RPM (375 for cold weather chip)
                bcc         .LD277              ; branch ahead if eng spd is less than this (eng not running)
;-----------------------------------------------------------
;            Engine has started
;            
;  Set A/C down counter to 12 and set engine started flag
;-----------------------------------------------------------
                ldab        init1HzStartDownCount   ; data value from XC7DF (usually 12)
                stab        startupDownCount1Hz     ; reset down-counter
                ldab        $205B
                orab        #$10                    ; set 205B.4 (one-time code bit)
                stab        $205B
;-----------------------------------------------------------
;  Always executed (all paths get here)
;  
;  After down-counter timeout, condition bit 205B.3 which
;  indicates very hot engine coolant.
;-----------------------------------------------------------
.LD277          pula                            ; pull the air cond load reading
                ldab        startupDownCount1Hz ; load 1Hz startup down-counter (maintained by RS comp. routine)
                bne         .LD298              ; branch ahead if counter is not zero

                ldab        coolantTempCount        ; load coolanf temp
                subb        acCoolantTempThreshold  ; subtract data value from XC7DD
                bcs         .LD290                  ; branch if ECT is hotter than 108 C (226 F)
                subb        acCoolantTempDelta
                bcc         .LD2A7                  ; branch if ECT is cooler than 105 C (221 F)
                ldab        $205B
                bitb        #$08                    ; test 205B.3
                beq         .LD2A7
                                                    ; <-- code branches here when ECT is hotter than 226 F
.LD290          ldab        $205B
                orab        #$08                    ; set 205B.3 (coolant temp is hotter than 226 F)
                stab        $205B
;-----------------------------------------------------------
;  Code branches here if countdown timer is not zero
;-----------------------------------------------------------
.LD298          clr         $205A               ; 205A is an up-counter used in this routine only
                ldab        $2059
                andb        #$FD                ; clr 2059.1 (used only in this routine)
                stab        $2059
                ldaa        #$00
                bra         .LD2F4
;-----------------------------------------------------------
; Two branches (above) to here.
;-----------------------------------------------------------
                                                ; <-- code branches here when ECT is cooler than 221 F
.LD2A7          ldab        $205B
                andb        #$F7                ; clr 205B.3 (coolant temp is cooler than 221 F)
                stab        $205B

                ldab        $2059               ; X2059.1 is used only in this routine                
ELSE
    
;-----------------------------------------------------------
; Old style A/C code starts here
;-----------------------------------------------------------
adcRoutine6     ldab        $2059               ; X2059.1 is used only in this routine

ENDC                                
                tsta                            ; test A/C reading
                bpl         .LD2CE              ; branch if < $80
                
;-----------------------------------------------------------
;           A/C Reading is >= $80 (A/C is ON)
;-----------------------------------------------------------
                bitb        #$02                ; test X2059.1 (used in this routine only)
                bne         .LD2E7              ; if set, branch ahead
                
                inc         $205A               ; increment X205A up-counter
                ldaa        $C7D0               ; for R3526, value is $0A
                cmpa        $205A               ; compare X205A counter with $0A
                bcc         .LD2EA              ; branch ahead if counter is GT $0A
                
                orab        #$02                ; set X2059.1
                clr         $205A               ; clr X205A counter
                stab        $2059
                bra         .LD2EA
                
;-----------------------------------------------------------
;           A/C Reading is < $80 (A/C is OFF)
;-----------------------------------------------------------
.LD2CE          bitb        #$02                ; test X2059.1 (used in this routine only)
                beq         .LD2E7
                
                inc         $205A               ; increment X205A up-counter
                ldaa        $C7D0               ; for R3526, value is $0A
                cmpa        $205A
                bcc         .LD2EA
                
                andb        #$FD                ; clr X2059.1 (used in this routine only)
                clr         $205A               ; reset X205A counter to zero
                stab        $2059
                bra         .LD2EA
;-----------------------------------------------------------
; Both above blocks branch to here if 2059.1 has already
; been set/clrd, otherwise they branch to LD2EA.
;-----------------------------------------------------------

.LD2E7          clr         $205A               ; reset X205A up-counter to zero

.LD2EA          bitb        #$02                ; test X2059.1 (set when A/C ON, clrd when OFF)
                beq         .LD2F2
                
                ldaa        #$FF                ; <-- A/C is ON, if jmp to LD49E, will set 008C.7
                bra         .LD2F4
;-----------------------------------------------------------
.LD2F2          ldaa        #$00                ; <-- A/C is OFF, if jmp to LD49E, will clr 008C.7


.LD2F4          tst         $00E2               ; test 00E2.7 (indicates RPM > 1627)
                bpl         .LD2FC              ; branch ahead (to skip jmp) if X00E2.7 is zero (RPM LT 1542)
                jmp         LD49E               ; jumps to separate block of code, uses value in A accum to
                                                ; set or clr X008C.7 and returns from there (RPM GT 1542)
;-----------------------------------------------------------
; Only 1 path here from above (RPM < 1627)
; A accum is $00 for OFF and $FF for ON
;-----------------------------------------------------------
                                                ; <-- RPM LT 1542
.LD2FC          ldab        $0085
                bitb        #$02                ; test X0085.1 (extra eng load?)
                bne         .LD315              ; branch ahead if bit is high
                
                ldab        $008A
                tsta                            ; test X0085.7 (low eng RPM?)
                bpl         .LD30E              ; branch ahead if X0085.7 is low
                
                andb        #$F3                ; clr X008A.3 and X008A.2 (to indicate A/C is ON)
                ldaa        $C1E5               ; for R3526, val is $2C (44 dec)
                bra         .LD327              ; branch to store values and return
;-----------------------------------------------------------
; Only 1 path to here from above
; Extra load bit is 0, RPM is low
;-----------------------------------------------------------
                                                ; X0085.7 is high
.LD30E          orab        #$0C                ; set X008A.3 and X008A.2 (to indicate A/C is OFF)
                ldaa        $C1E5               ; for R3526, val is $2C (44 dec)
                bra         .LD327              ; branch to store values and return
;-----------------------------------------------------------
; Only 1 path here when 0085.1 is high (extra eng load?)
;-----------------------------------------------------------
.LD315          ldab        $008A               ; load X008A bits value
                andb        #$0C                ; mask X008A.3 and X008A.2
                tsta                            ; A was loaded with $00 or $FF (above)
                bpl         .LD32C              ; branch down to next section if A is 00
;-----------------------------------------------------------
; A = $FF, A/C is ON
;-----------------------------------------------------------
                cmpb        #$0C                ; A is $FF, check for both X008A.3 and X008A.2 high
                bne         .LD32B              ; return if both bits not high
                
                ldab        $008A               ; clear both
                andb        #$F3                ; clr X008A.3 and X008A.2
                ldaa        $C1E5               ; for R3526, val is $2C (44 dec)


.LD327          stab        $008A               ; store bits value
                staa        $00B8               ; store counter value

.LD32B          rts
;-----------------------------------------------------------
; A = $00, A/C is OFF    (Only 1 path here from above)
;-----------------------------------------------------------
.LD32C          cmpb        #$04
                bne         .LD32B              ; return if X008A not $04 (X008A.3 low, X008A.2 high)
                
                ldab        $008A               ; else, set them that way
                orab        #$08                ; set X008A.3
                andb        #$FB                ; clr X008A.2
                ldaa        $C1E6               ; for R3526, value is $2C (44 dec)
                bra         .LD327              ; branch up to store and return
code

IF ZERO

;---------------------------------------------------------------------------------------------------------------
; This is the Griffith version of the A/C Service Routine
;---------------------------------------------------------------------------------------------------------------

code

adcRoutine6	    ldab	    $2059
		        tsta
		        bpl	        .LD1F1
;-----------------------------------------------------------
;           A/C Reading is >= $80 (A/C is ON)
;-----------------------------------------------------------
		        bitb	    #$02
		        bne	        .LD20A
		        
		        inc	        $205A
		        ldaa	    $C7D0
		        cmpa	    $205A
		        bcc	        .LD20D
		        
		        orab	    #$02		        
		        clr	        $205A
		        stab	    $2059
		        bra	        .LD20D
;-----------------------------------------------------------
;           A/C Reading is < $80 (A/C is OFF)
;-----------------------------------------------------------
.LD1F1		    bitb	    #$02
	            beq	        .LD20A
	            
	            inc	        $205A
	            ldaa	    $C7D0
	            cmpa	    $205A
	            bcc	        .LD20D
	            
	            andb	    #$FD
	            clr	        $205A
	            stab	    $2059
	            bra	        .LD20D
;-----------------------------------------------------------
; Both above blocks branch to here if 2059.1 has already
; been set/clrd, otherwise they branch to LD2EA.
;-----------------------------------------------------------
.LD20A		    clr	        $205A

.LD20D		    bitb	    #$02
		        beq	        .LD215
		        ldaa	    #$FF
		        bra	        .LD217
;-----------------------------------------------------------
.LD215		    ldaa	    #$00

.LD217		    tst	        $00E2
		        bpl	        .LD21F
		        ;jmp	        air_cond_load_sr
                jmp         LD49E
;-----------------------------------------------------------
; Only 1 path here from above (RPM < 1627)
; A accum is $00 for OFF and $FF for ON
;-----------------------------------------------------------
.LD21F		    ldab	    $0085
		        bitb	    #$02
		        bne	        .LD238
		        ldab	    $008A
                tsta
		        bpl	        .LD231
    		    andb	    #$F3
        		ldaa	    $C1E5
        		bra	        .LD24A
;-----------------------------------------------------------
; Only 1 path to here from above
; Extra load bit is 0, RPM is low
;-----------------------------------------------------------
.LD231		    orab	    #$0C
		        ldaa	    $C1E5
		        bra	        .LD24A
;-----------------------------------------------------------
; Only 1 path here when 0085.1 is high (extra eng load?)
;-----------------------------------------------------------
.LD238		    ldab	    $008A
		        andb	    #$0C
	            tsta
		        bpl	        .LD24F
;-----------------------------------------------------------
; A = $FF, A/C is ON
;-----------------------------------------------------------
		        cmpb	    #$0C
		        bne	        .LD24E
		        
		        ldab	    $008A
		        andb	    #$F3
		        ldaa	    $C1E5
		        
.LD24A		    stab	    $008A
		        staa	    $00B8
		        
.LD24E		    rts
;-----------------------------------------------------------
; A = $00, A/C is OFF    (Only 1 path here from above)
;-----------------------------------------------------------
.LD24F		    cmpb	    #$04
		        bne	        .LD24E
		        
		        ldab	    $008A
		        orab	    #$08
		        andb	    #$FB
		        ldaa	    $C1E6
		        bra	        .LD24A


ENDC
