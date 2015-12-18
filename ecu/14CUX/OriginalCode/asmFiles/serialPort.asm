;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:    Serial Port (SCI) Service Routine
;
;   The serial port is set up as follows:
;       Rate and Mode Control Register  (addr $10) is set to $05
;       Xmt/Rcv Control Status Register (addr $11) is set to $0A
;
;   This sets the divider to (1 MHz/128) for a baud rate of 7812.5 (8-N-1).
;   No serial port interrupts are used.
;
;   This routine is periodically called by the main loop. The I2C routine
;   shuts off the serial port temporarily (replaces $0A with $00) if it needs
;   to communicate with the OBDD but this happens only at startup and if an
;   OBDD is connected.
;
;   The number of read bytes can be controlled between 1 and 16 and then jumps
;   to the preset numbers of 80, 100, 400 and 512 bytes (see table at end of
;   file).
;
;   There are 2 independent transactions that can take place.
;       1) Address/Quantity Transaction
;       2) Read/Write Transaction
;
;
;   Address/Quantity Transaction
;   ----------------------------
;   1st byte: 0qqq qqMM     bit 7 is zero, bits 6:2 are qty (read only),
;                           bits 1:0 become bits 15:14 of desired address
;
;   2nd byte: nnnn nnnn     this byte becomes bits 13:6 of desired address and
;                           must be sent quickly after 1st byte due to timeout
;                            
;                            (address is now MMnn nnnn nnxx xxxx)
;
;   Read/Write Transaction
;   ----------------------
;   Read (1 byte required):  11pp pppp
;                           bit 7 is one, bit 6 (r/w) is one, bits 5:0 become
;                           the last 6 address bits
;
;   Write (2 bytes required)
;    1st byte: 10pp pppp    bit 7 is 1, bit 6 is zero, bits 5:0 become the
;                           the last 6 address bits (MMnn nnnn nnpp pppp)
;
;    2nd byte: rrrr rrrr    8-bit data to write (send quickly due to timeout)
;
;   Quantity examples:
;    00 = 0000 00xx =   1 
;    3c = 0011 11xx =  16
;    40 = 0100 00xx =  80 bytes (0050 hex)
;    44 = 0100 01xx = 100 bytes (0064 hex)
;    48 = 0100 10xx = 400 bytes (0190 hex)
;    4C = 0100 11xx = 512 bytes (0200 hex)
;
;------------------------------------------------------------------------------

code

sciService      sei                             ; set interrupt mask
                ldab        $00E5               ; index offset (starts at zero due to 00E7 timeout)
                inc         $00E7               ; timeout counter
                bne         .LF9CC              ; branch ahead if not zero
                clrb

.LF9CC          stab        $00E5               ; 00E5 is clrd cond on 00E7
                                                ; ldx #$F9DE (see below)
                ldx         #.sci1              ; load sciRoutine1
                abx                             ; add B to X
                ldd         sciTRCS             ; load control/status and rcv reg
                asla                            ; this tests rcv reg full flag
                bcc         .LF9DC              ; branch ahead if no rcv data
                clr         $00E7               ; char rcvd! reset the timer
                tba                             ; transfer char to A
                sec                             ; set carry flag

.LF9DC          jmp         $00,x               ; jump to sciRoutine1 + Index
;------------------------------------------------------------------------------

.sci1           bcc         .LF9F0              ; return if no rcv data
                bmi         .LFA0B              ; bra ahead if bit 7 set (7 = transaction 2)
                staa        $00E8               ; store rcvd char at 00E8
                ldab        #$1B                ; load B with #1B (3rd index offset)

.LF9E6          stab        $00E5               ; store index offset

.LF9E8          ldab        sciTRCS             ; read control/status
                bitb        #$20                ; check TDRE bit
                beq         .LF9E8              ; loop back if waiting for xmt
                staa        sciTxData           ; echo rcv char

.LF9F0          rts                             ; return
;------------------------------------------------------------------------------
                bcc         .LF9F0              ; return if no rcv data
                bsr         .LFA18              ; X = 00EB + 00E6
                staa        $00,x
                bra         .LFA08              ; see below
;------------------------------------------------------------------------------
                bcc         .LF9F0              ; return if no rcv data (2nd char?)
                psha                            ; push A (2nd rcv char?)
                tab                             ; 2nd char in B (0000 00YY)
                ldaa        $00E8               ; 1st char in A (XXXX XXXX)
                asld
                asld
                asld
                asld
                asld
                asld                            ; (YYXX XXXX XX00 0000)
                std         $00EB               ; store shifted 2-char value (address now formed in 00EB/EC)
                pula                            ; pull 2nd rcvd char

.LFA08          clrb
                bra         .LF9E6              ; str 0 at E5, echo 2nd char
;------------------------------------------------------------------------------
                                                ; branches here if bit 7 is set
.LFA0B          tab
                andb        #$3F                ; mask to just bits 5:0
                stab        $00E6               ; store 5-bit value at 00E6
                bita        #$40                ; test bit 6 in rcvd char
                bne         .LFA1E              ; branch if bit 6 is 1 (read op) to xmt serial char(s)
                ldab        #$13                ; this index offset waits for final write value
                bra         .LF9E6              ; store $13 at E5, echo 1st transaction 2 char and return
;------------------------------------------------------------------------------
                                                ; this is a subroutine called by both read and write code
.LFA18          ldx         $00EB               ; it creates the fully formed 16-bit address
                ldab        $00E6
                abx
                rts
;------------------------------------------------------------------------------
;   If the qty field in the read byte is less than $11, the routine will read
;   the specified qty (1 thru 16 dec), otherwise the qty will taken from the
;   table at the end of the file.
;------------------------------------------------------------------------------
                                                ; *** Read Routine ***
.LFA1E          bsr         .LFA18              ; create index from 00EB + 00E6
                stx         $00E9               ; store it at 00E9
                clra
                ldab        $00E8               ; retrieve original address byte (qqqq qqaa)
                lsrb                            ; (0qqq qqqa)
                lsrb                            ; (00qq qqqq)
                incb                            ; add 1
                cmpb        #$11                ; val of 40h gives 11h
                bcs         .LFA33              ; branch ahead if B < $11 (qty will be 1 thru 16)
                aslb                            ; get qty from table
                ldx         #.was.FA31          ; load X with #FA31
                abx                             ; add B to X

.was.FA31       ldd         $00,x               ; load 16-bit qty from indexed loc


.LFA33          addd        $00E9               ; add address to qty
                std         $00ED               ; and store it here as compare value to stop loop
                                                ;*** RE-ENTRY POINT FOR MULTIPLE READ ***
                ldx         $00E9               ; get the updated address pointer
                ldab        #$59                ; index offset for xmt loop
                stab        $00E7               ; timer keeps getting reset to this convenient value
                ldaa        sciTRCS             ; read SCI control/status
                bita        #$20                ; test for xmt reg empty
                beq         .LFA4F              ; branch ahead if still full
                ldaa        $00,x               ; xmt bfr ptr = 00E9/EA, get char
                staa        sciTxData           ; transmit char
                inx                             ; increment bfr ptr
                stx         $00E9               ; restore it
                cpx         $00ED               ; compare it with 00ED/EE
                bne         .LFA4F
                clrb

.LFA4F          stab        $00E5               ; clears 00E5
                cli                             ; clear interrupt mask
                rts                             ; and return
;------------------------------------------------------------------------------
;    Preset serial port read quantities
;------------------------------------------------------------------------------
;.LFA53

                DW          $0050               ;  80 bytes
                DW          $0064               ; 100
                DW          $0190               ; 400
                DW          $0200               ; 512
code
