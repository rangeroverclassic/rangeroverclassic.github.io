;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 06-Jan-2014
;
;   Description:
;       Code specific to R3365 (Defender).
;
;------------------------------------------------------------------------------

code

LFA46       ldaa	$008B           ; bits value
		  	brn	    LFA4A           ; branch never
		  	
LFA4A		ldab	AdcStsDataHigh
		   	bitb	#$40            ; test ADC busy flag
		   	bne	    LFA4A           ; branch back if busy
		   	bitb	#$20            ; test comparator flag
		   	beq	    LFA5B           ; 0 means Vin < Vp, 1 means Vin > Vp

		   	oraa	#$80            ; 
		   	staa	$008B           ; set 008B.7
		   	bra	    LFA71
		                  
LFA5B		bita	#$80
		   	beq	    LFA71
		   	anda	#$7F            ; clear 008B.7
		   	staa	$008B
		   	inc	    $2002           ; this is the road speed sawtooth
		   	ldd	    $2049           ; increm in RS comp s/r (ramp 0 to FFFF)
		   	addd	#$0001
		   	bcs	    LFA71
		   	std	    $2049
LFA71	   	rts

code
