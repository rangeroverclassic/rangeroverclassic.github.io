///////////////////////////////////////////////////////////////////////////////////////////////
//
//  MAF Linearization and Fuel Map Row Index 
//      (dhb 21-Feb-2014)
//
//  This is a model of two sections of 14CUX code from the spark interrupt. The first section
//  is the MAF linearization. This is for the 3AM/5AM hotwire air flow meter. According to L-R,
//  the MAF should output from 1.3 to 1.5 volts at idle. Maximum possible value is 5 volts.
//  The second section calculates the load based row index into the fuel map. Although there
//  are only 8 rows, the index value can range from 0x00 to 0x70 with 16 steps of resolution
//  into each row. Interpolation is used later when determininag the map value.
//
//  In the attempt to do as literal a translation as possible, we use the goto command as well
//  as byte/word unions.
//
///////////////////////////////////////////////////////////////////////////////////////////////

/*
;--------------------------------------------------------------------------------------------
;                         MAF Sensor Linearization 
;
; This section executes unless the MAF failure bit is set. It linearizes the  MAF output and
; stores the 16-bit result (normally in X204D/4E) for later use in determining the fuel map
; row (load based) index.
;
; The MAF reads about 300 decimal at idle and the maximum possible value is 10 bits or 1023
; decimal. This results in a linearized range of approximately 600 at idle to slightly over
; 17,000 decimal.
;
; The loop part of this code is a 16-bit squaring function:
;       Input:      16-bit value in AB
;       Output:     (AB * AB) / 0x10000
;
; When entering this section of code, 0x00C8/C9 holds the sum of MAF Low and MAF High. The
; squaring loop is run twice. The 'C' code equivalent of the whole code section is listed
; here:
;
;       x = 8 * mafSum + 8797;
;       x = (UINT16)((x * x) / 0x10000);
;       x = (UINT16)(2 * (2 * x - 2496));
;       x = (UINT16)((x * x) / 0x10000);
;       Store result in 00CA/CB for use in 16-bit mpy (for FM row index calc)
;       Store result in 004D/4E for use elsewhere
;
;--------------------------------------------------------------------------------------------
.linearizeMaf   ldd         $00C8               ; reload MAF sum
                asld                            ; 2x
                asld                            ; 4x
                asld                            ; 8x
                addd        $C1C3               ; data value is $225D (8797 dec)

.linMafLoop     staa        $00C8               ; squaring function starts here
                mul
                staa        $00C9
                ldaa        $00C8
                tab
                mul
                addb        $00C9
                adca        #$00
                addb        $00C9
                adca        #$00                ; squaring function ends here
                
                com         $00CE               ; previously cleared at code address LDCEB
                beq         .LDF30              ; 1's comp forced branch out here on 2nd pass
                asld
                subd        $C1C5               ; data value is $09C0 (2496 dec)
                bcc         .LDF2D
                ldd         #$0000              ; if negative, limit to zero

.LDF2D          asld
                bra         .linMafLoop         ; end loop

.LDF30          std         $00CA               ; store it here for 16-bit mpy
                std         mafLinear           ; also store it in normal location

---------------------------------------------------------------------------------------------------




;---------------------------------------------------------------------------------------------------
;                *** Calculate Fuel Map Load Value (Row Index) ***
;
; This value, which is normally stored at X005B, is calculated from both air flow and engine speed.
;
; The Linearized MAF is calculated above and is stored in the normal X004D/4E locations and the
; X00CA/CB temporary location.
;
; The row index value is clipped low at 0x00 and high at 0x70 so that it is confined to the range
; of the 8 row fuel map table.
;   
;---------------------------------------------------------------------------------------------------
                ldd         ignPeriod           ; load 16-bit ignition period (instantaneous)
                jsr         mpy16               ; call 16-bit mpy routine, mpy ignPeriod by mafLinear
                subd        $C1C7               ; data value is $001E (subtract this)
                bcc         .LDF61              ; branch ahead if value is still positive
                clra                            ; else, clear A
                bra         .LDF6F              ; and branch

.LDF61          lsrd                            ; logical shift right double
                tsta                            ; test A for zero
                bne         .LDF6D              ; branch ahead to load $70
                ldaa        $200A               ; X200A gets initialized from fuel map byte offset $10A
                mul
                cmpa        #$70                ; compare A with $70
                bcs         .LDF6F              ; if A <= $70, branch to store as fuel map row index

.LDF6D          ldaa        #$70                ; else store $70

.LDF6F          staa        fuelMapLoadIdx      ; store value as 'fuelMapLoadIdx'

;---------------------------------------------------------------------------------------------------
*/

#include <stdio.h>
#include <conio.h>

typedef   signed char  CHAR;
typedef unsigned char  UCHAR;
typedef unsigned char  UINT8;
typedef unsigned short UINT16;
typedef unsigned long  DWORD;


#define A 1     // these are reversed due to the endian issue
#define B 0

#define C8 1    // (ditto)
#define C9 0


// The A and B accumulators can be used as separate 8-bit registers
// or together as a 16-bit register. A union is perfect for modelling this.
// X00C8 and X00C9 are used in a similar way
union ABunion
{
   UINT16 ab;
   UCHAR  r[2];
};

ABunion reg;                               // the AB register pair


union memUnion
{
   UINT16 c8c9;
   UCHAR  m[2];
};

memUnion mem;                               // 16-bit memory location



///////////////////////////////////////////////////////////////////////////////
//
//  LinearizeMAFin_C
//
//  This is my understanding of what the assembly language code is actually
//  doing.
//
///////////////////////////////////////////////////////////////////////////////
UINT16 linearizeMAF_C (UINT16 mafSum)
{
    UINT16  XC1C3 = 0x225D;
    UINT16  XC125 = 0x09C0;
	UINT16 x;


	x = 8 * mafSum + XC1C3;
	x = (UINT16)((x * x) / 0x10000);

    if (x > 2496/2)
	    x = (UINT16)(2 * (2 * x - XC125));
    else
        x = 0;

	x = (UINT16)((x * x) / 0x10000);

    return (x);

}


///////////////////////////////////////////////////////////////////////////////
//
//  LinearizeMAF_6803
//
//  This a literal translation of the 6803 assembly code.
//
//  Note about possible compiler hazard...
//  Although there are arithmetic shifts, they are left shifts, so there
//  should be no problem with possible differences in compiler implementation
//  (logical vs arithmetic).
//
///////////////////////////////////////////////////////////////////////////////
UINT16 linearizeMAF_6803 (UINT16 mafSum)
{
    UINT16  XC1C3 = 0x225D;
    UCHAR   X00CE = 0;
    UINT16  X00CA;
    UINT16  X204D;
    UINT16  XC125 = 0x09C0;


    mem.c8c9 = mafSum;

//LDF03:
    reg.ab = mem.c8c9;                      // ldd   X00C8
    reg.ab <<= 1;                           // asld
    reg.ab <<= 1;                           // asld
    reg.ab <<= 1;                           // asld
    reg.ab += XC1C3;                        // addd  XC1C3

LDF0E:
    mem.m[C8] = reg.r[A];                   // staa  X00C8
    reg.ab = reg.r[A] * reg.r[B];           // mul
    mem.m[C9] = reg.r[A];                   // staa  X00C9
    reg.r[A] = mem.m[C8];                   // ldaa  X00C8
    reg.r[B] = reg.r[A];                    // tab
    reg.ab = reg.r[A] * reg.r[B];           // mul
    reg.ab += mem.m[C9];                    // addb  X00C9, adca  #$00
    reg.ab += mem.m[C9];                    // addb  X00C9, adca  #$00
    X00CE = ~X00CE;                         // com  (1's complement)
    if (!X00CE) goto LDF30;                 // beq   LDF30
    reg.ab <<= 1;                           // asld
    reg.ab -= XC125;                        // subd  XC1C5
    if (!(reg.ab & 0x8000)) goto LDF2D;     // bcc   LDF2D
    reg.ab = 0x0000;                        // ldd   #$0000
LDF2D:
    reg.ab <<= 1;                           // asld
    goto LDF0E;                             // bra   LDF0E

LDF30:
    X00CA = reg.ab;                         // std   X00CA
    X204D = reg.ab;                         // std   X204D

    return X204D;
}


///////////////////////////////////////////////////////////////////////////////
//
//  Calculate_Row_Index
//
//  There are two values in this formula that come from the data section of the
//  PROM. They are:
//  
//  X2005 - This is a multiplier factor that is pulled from the current fuel
//          map at offset $10A. This is the first value after the map's ADC
//          control table. It is stored in RAM location X2005 for use. This
//          is a byte value and is often (but not always) $B2.
//
//  XC1C7 - This is a 16-bit value in the data section. It is outside of the
//          fuel map data and does not change with fuel map changes. This
//          value is typically $001E.
//
//  This routine takes the ignition period and the linearized MAF readings as
//  arguments and returns the 8-bit row index value (clipped between $00 min
//  and $70 max).
//
///////////////////////////////////////////////////////////////////////////////
UINT8 Calculate_Row_Index (UINT16 ignitionPeriod, UINT16 linearMAF)
{
    UINT8  X2005 = 0xB2;
    UINT16 XC1C7 = 0x001E;

    reg.ab = ignitionPeriod;                        // ldd         ignPeriod
    reg.ab = (UINT16)((reg.ab * linearMAF) >> 16);  // jsr         mpy16
    if (reg.ab > XC1C7) {
        reg.ab -= XC1C7;                            // subd        $C1C7
        goto LDF61;                                 // bcc         .LDF61
    }

    reg.r[A] = 0;                                   // clra
    goto LDF6F;                                     // bra         .LDF6F

LDF61:                                              // .LDF61       lsrd
                                                    //
    if (reg.r[A] != 0)                              // tsta                       
        goto LDF6D;                                 // bne         .LDF6D   

    reg.r[A] = X2005;                               // ldaa        $200A          
    reg.r[A] = (reg.r[A] * reg.r[B]) >> 8;          // mul
    if (reg.r[A] <= 0x70)                           // cmpa        #$70           
        goto LDF6F;                                 // bcs         .LDF6F         

LDF6D:  reg.r[A] = 0x70;                            // .LDF6D          ldaa        #$70           

LDF6F:  return (reg.r[A]);                          // .LDF6F          staa        fuelMapLoadIdx 

}



///////////////////////////////////////////////////////////////////////////////
//  
//  Main program.
//
//  This scans through the MAF voltage range and calls the routines above.
//
///////////////////////////////////////////////////////////////////////////////
void main(void)
{
    UINT16 mafCounts;
    FILE *fptr;
    UINT16 linearVal1, linearVal2;
    UINT8 rowIndex[3];

	fptr = fopen("mafAndRowIndex.txt", "w");

    if (fptr) {
            fprintf( fptr, "MAF Volts   MAF Counts   Linear C    Linear 6800    900  3100  5102\n");
            fprintf( fptr, "--------------------------------------------------------------------\n");
    }

	for (mafCounts = 0; mafCounts < 1024; mafCounts += 20) {

        linearVal1 = linearizeMAF_C (2 * mafCounts);

        linearVal2 = linearizeMAF_6803 (2 * mafCounts);

        rowIndex[0] = Calculate_Row_Index (0x208D, linearVal2);     //  900 RPM
        rowIndex[1] = Calculate_Row_Index (0x0973, linearVal2);     // 3100 RPM
        rowIndex[2] = Calculate_Row_Index (0x0553, linearVal2);     // 5102 RPM


        if (fptr)
            fprintf( fptr, "%5.2f  \t  %5u  \t  %5u  \t  %5u    0x%02X  0x%02X  0x%02X\n", 
              ((mafCounts/1023.0)*5.0), mafCounts, linearVal1, linearVal2, rowIndex[0], rowIndex[1], rowIndex[2]);
    }

    if (fptr)
        fclose(fptr);

}
