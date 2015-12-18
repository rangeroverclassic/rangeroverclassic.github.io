;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       Contains miscellaneous routines.
;
;------------------------------------------------------------------------------

code

;------------------------------------------------------------------------------
; This routine manipulates bits in X00E2. It is called from two places in
; the ICI.
;------------------------------------------------------------------------------
LF416           ldaa        $00E2               ; load bits value
                bita        #$22                ; test X00E2.5 and X00E2.1
                beq         .LF422              ; return if both bits are low
                
                oraa        #$01                ; set X00E2.0
                anda        #$CD                ; clr X00E2.5, X00E2.4 and X00E2.1
                staa        $00E2               ; store bits value

.LF422          rts                             ; return

;------------------------------------------------------------------------------
;               Set/Clr Bits That Control Open / Closed Loop
;
; This routine is called from 2 places. Once from ICI and once from the
; throttle pot routine.
;------------------------------------------------------------------------------
LF423           ldd         throttlePot         ; 10-bit value
                lsrd
                lsrd                            ; shift right 2 bits (only top 8 of 10 bits in B)
                ldaa        $0087               ; load bits value
                ldx         ignPeriod           ; load ignition period into X
                cpx         $C0A7               ; (X - M) data value is $089D (3400 RPM)
                bcc         .LF44B              ; branch ahead if engine speed < 3400 RPM
                
;-------------------------------
; RPM > 3400
;-------------------------------
                oraa        #$20                ; set X0087.5 (when eng speed is > 3400 RPM)
                bra         .LF44D
                
;-------------------------------
; Code branches here from below
; when throttle < about 91%
; (84% for Griff)
;-------------------------------
.LF434          ldaa        $0087
                anda        #$F7                ; clr X0087.3 (TPS < 91%)
                staa        $0087
                ldaa        $008C
                anda        #$F7                ; clr X008C.3
                staa        $008C
                bra         .LF4A9
;-------------------------------
; Code branches here from below
; when fuel map row index < $30
; or RPM < 1838
;-------------------------------
.LF442          ldab        $008C
                andb        #$F7                ; clr X008C.3
                stab        $008C
                clra                            ; clr A to store in X006C
                bra         .LF4A7
                
;-------------------------------
; RPM < 3400
;-------------------------------
.LF44B          anda        #$DF                ; clr X0087.5 (when eng speed is < 3400 RPM)

;-------------------------------
; Code gets here for both RPM
; conditions.
;-------------------------------
.LF44D          staa        $0087               ; store value after X0087.5 set or cleared
                cpx         #$1770              ; compare eng speed with 1250 RPM
                bcc         .LF45A              ; branch ahead if eng speed is < 1250 RPM
                
                ldaa        $0088               ; if here, RPM > 1250
                oraa        #$10                ; set X0088.4 when RPM > 1250 (purge valve related?)
                staa        $0088

.LF45A          cmpb        $C0A6               ; value is $EA (Griff= $D7) (cmpr with top 8 bits of TPS)
                bcs         .LF434              ; branch up if less TPS < 91% (84% for Griff)

                ldaa        $0087               ; if here, throttle > 91%
                oraa        #$08                ; set X0087.3
                staa        $0087
                ldaa        fuelMapLoadIdx      ; load fuel map row index
                cmpa        #$30                ; compare with 0x30
                bcs         .LF442              ; branch up if row index < 0x30

                cpx         #$0FF0              ; cmpr ignition period with $0FF0 (1838 RPM)
                bcc         .LF442              ; branch up if RPM < 1838 RPM
                
;-------------------------------
; If here:
;   TPS > 91%
;   F.M. Row Index > $30
;   Eng. speed > 1838 RPM
;
;-------------------------------
                ldd         ignPeriod           ; if here, ignit period can be shifted into B
                lsrd
                lsrd
                lsrd
                lsrd                            ; upper 8 bits are now in B accumulator
                ldaa        #$FF                ; load FF into A
                sba                             ; subtract B from A
                bcs         .LF442              ; branch up if carry set (will this ever happen??)


                ldab        $C0A9               ; data value is $01
                mul
                cmpa        #$00
                bne         .LF489
                
                tba                             ; xfr B to A
                cmpa        $2010               ; value at 2010 is 51h (81 dec)
                bcs         .LF48C              ; if LT 81, load 81

                                                ; $2010 is initialized from the 2nd last value in the fuel map
.LF489          ldaa        $2010               ; this value is in the range of $51 to $68

.LF48C          ldab        $008C
                orab        #$08                ; set X008C.3 (when set, open loop is forced)
                stab        $008C
                ldab        faultBits_4C
                bitb        #$40                ; test VSS fault bit (road speed)                
                beq         .LF4A7              ; branch ahead if no fault
                
                ldab        roadSpeed           ; load road speed
                bne         .LF4A7              ; branch ahead if road speed not zero

                ldab        fuelMapNumber       ; road speed is zero, load fuel map number
                beq         .LF4A6              ; branch ahead if fuel map zero
                
                cmpb        #$05                ; compare with 5
                bne         .LF4A7              ; branch ahead if NOT fuel map 5

.LF4A6          clra
;---------------------------------------
                                                ; can branch here from above
.LF4A7          staa        $006C               ; throttle pot related counter (reset to value in X2010)
;---------------------------------------
                                                ; can branch here from above
.LF4A9          ldd         throttlePot
                subd        #$007C              ; subtract $7C (about 12%)
                bcs         .LF4C0              ; return if TPS < 12%
                
                ldaa        $0086
                anda        #$7E                ; clr X0086.7 and X0086.0
                oraa        #$04                ; set X0086.2
                staa        $0086
                ldaa        $2059
                anda        #$FB                ; clr X2059.2
                staa        $2059

.LF4C0          rts


;----------------------------------------------------------------------------------
; This subroutine is Called from Engine Coolant Temperature service routine only.
;
; Uses X2012 which is the current O2 reading (either bank). This value is about
; 50 to 60 count for a high and zero for a low.
;
; Values potentially written here:
;
; Address   Bank
; -----------------------
; X2013/14  Right (these 2 16-bit values countdown repeatedly from 200 to zero)
; X2015/16  Left
; X2017     Right (these 2 values are signed, init to -1 and vary between -1 and +9)
; X2018     Left
; X2019     Right
; X201A     Left
; X201B     Right (these values are added to the O2 reference (a bias or offset)
; X201C     Left
;
;----------------------------------------------------------------------------------
LF4C1           ldab        $0089               ; load bits value
                andb        #$07                ; mask X0089.2, X0089.1 and X0089.0
                bne         .LF4DA              ; return if any of 3 bits are high
                ldab        $2012               ; latest O2 reading
                cmpb        #$0F                ; compare with 15
                bcc         .LF4DA              ; rtn if O2 reading > 15 (rich condition)
                
                ldaa        $2004               ; load bits value
                tst         $0088               ; test bank indicator bit X0088.7
                bmi         .LF4FB              ; branch if right bank
;------------------------------------------------
; Left Bank
;------------------------------------------------
                bita        #$08                ; test X2004.3
                bne         .LF4DB              ; branch to continue if set

.LF4DA          rts                             ; X2004.3 is zero, so return
;------------------
.LF4DB          ldx         $2015               ; normally cycles from 200 to 0
                dex                             ; decrement X2015/16 (range 0 to 200)
                stx         $2015               ; 
                bne         .LF525              ; branch ahead if 2015/16 is not zero (most times)
                                                ;  (this code executes every 200th time)
                ldx         $C1FC               ; val is $00C8 (200 dec)
                stx         $2015               ; reset X2015/16 to 200
                bita        #$20                ; test X2004.5
                bne         .LF550              ; if bit 5 is 1, branch ahead to left bank code
                oraa        #$20                ; set bit 5 and continue
                staa        $2004               ; 
                ldaa        $2018               ; 
                staa        $201A               ; 
                bra         .LF562              ; branch down to reset X2018 to minus 1 and return
;------------------------------------------------
; Right Bank
;------------------------------------------------
.LF4FB          bita        #$04                ; test X2004.2
                bne         .LF500              ; branch to continue if set
                
                rts                             ; X2004.2 is zero, so return
;------------------
.LF500          ldx         $2013               ; normally cycles from 200 to 0
                dex                             ; decrement X2013/14 (range 0 to 200)
                stx         $2013               ; 
                bne         .LF520              ; branch ahead if 2013/14 is not zero (most times)
                                                ;  (this code executes every 200th time)
                ldx         $C1FC               ; val is $00C8 (200 dec)
                stx         $2013               ; reset X2013/14 to 200
                bita        #$10                ; test X2004.4
                bne         .LF538              ; if bit 4 is 1, branch ahead to right bank code
                oraa        #$10                ; set bit 4 and continue
                staa        $2004               ; 
                ldaa        $2017               ; 
                staa        $2019               ; 
                bra         .LF54A              ; branch down to reset X2017 to minus 1 and return


.LF520          ldaa        $2017               ; 
                bra         .LF528              ; 

.LF525          ldaa        $2018               ;

.LF528          cba                             ; (A minus B)  A=(2017 or 2018)  B=(2012)
                bcs         .LF537              ; rtn if A is less than B
                tst         $0088               ; test bank indicator bit
                bmi         .LF534              ;
                stab        $2018               ;
                rts
;------------------------------------------------
                                                ; 0088.7 high
.LF534          stab        $2017               ;

.LF537          rts

;------------------------------------------------
; Right Bank
;------------------------------------------------
.LF538          clra                            ; 
                ldab        $2017               ; varies from -1 to small positive (single digit)
                subb        $2019               ; (stayed zero for RTs)
                bcs         .LF547              ; 
                cmpb        $C1FA               ; val is $02
                bcs         .LF547              ; (always branched for RTs?)
                tba                             ; 

.LF547          staa        $201B               ; 201B is used to bias O2 ref (201B stayed zero for both RTs)

.LF54A          ldaa        #$FF                ; reset X2017 to -1
                staa        $2017               ; 
                rts                             ; 
                
;------------------------------------------------
; Left Bank
;------------------------------------------------
.LF550          clra                            ; 
                ldab        $2018               ; varies from -1 to small positive (single digit)
                subb        $201A               ; (stayed zero for RTs)
                bcs         .LF55F              ; 
                cmpb        $C1FA               ; val is $02
                bcs         .LF55F              ; (always branched for RTs?)
                tba                             ; 

.LF55F          staa        $201C               ; 201C is used to bias O2 ref (201C stayed zero for both RTs)

.LF562          ldaa        #$FF                ; reset X2018 to -1
                staa        $2018               ; 
                rts                             ; 
                
;------------------------------------------------------------------------------
;                   Restore Battery Backed Values
;
; This routine looks for differences between the MPU's internal battery-backed
; RAM and (X0040 to X0052) external RAM (X2060 to X2072) and re-ininitializes
; the battery-backed values if a difference exists.
;
; This is called only by ICI routine.
;
;------------------------------------------------------------------------------
initRAMFromExt  ldd         secondaryLambdaR
                subd        $2060
                beq         .LF574
                ldd         #$8000
                std         secondaryLambdaR

.LF574          ldd         secondaryLambdaL
                subd        $2064
                beq         .LF580
                ldd         #$8000
                std         secondaryLambdaL

.LF580          ldd         longLambdaTrimR     ; left long-term trim
                subd        $2062
                beq         .LF58C              ; if different...
                ldd         #$8000              ;  reset to neutral value
                std         longLambdaTrimR

.LF58C          ldd         longLambdaTrimL     ; right long-term trim
                subd        $2066
                beq         .LF598              ; if different...
                ldd         #$8000              ;   reset to neutral value
                std         longLambdaTrimL

.LF598          ldd         hiFuelTemperature   ; checks two 8-bit values
                subd        $2068               ;   X0048 = hiFuelTemperature
                beq         .LF5A4              ;   X0049 = faultBits_49
                ldd         #$0000
                std         hiFuelTemperature

.LF5A4          ldd         faultBits_4A        ; checks two fault bytes
                subd        $206A               ;   X004A and X0048
                beq         .LF5B0              ; and zeros them, if different
                ldd         #$0000
                std         faultBits_4A

.LF5B0          ldd         faultBits_4C        ; checks two fault bytes
                subd        $206C               ;   X004C and X004D
                beq         .LF5BC              ; and zeros them, if different
                ldd         #$0000
                std         faultBits_4C

.LF5BC          ldd         faultBits_4E        ; check fault byte X004E and value in X004F
                subd        $206E
                beq         .LF5CF              ; if different,
                clra                            ; set fault byte X004E to zero
                ldab        $C242               ; and set X004F to data value at XC242
                std         faultBits_4E
                ldaa        $008C
                oraa        #$40                ; set X008C.6 (data corrupted or RAM fail)
                staa        $008C


.LF5CF          ldd         throttlePotMinimum  ; 16-bit value at X0051/52
                subd        $2071
                beq         .LF5E3              ; if different...
                ldd         #$0070              ; reset to default value of $0070
                std         throttlePotMinimum
                std         throttlePotMinCopy
                ldaa        $008C
                oraa        #$40                ; set X008C.6 (data corrupted or RAM fail)
                staa        $008C

.LF5E3          ldaa        fuelMapNumberBackup ; check fuel map number
                suba        $2070
                beq         .LF5EF              ; if different
                ldaa        fuelMapNumber       ; re-init battery-backed value
                staa        fuelMapNumberBackup

.LF5EF          rts
;------------------------------------------------------------------------------

code
