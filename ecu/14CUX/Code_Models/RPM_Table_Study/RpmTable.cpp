///////////////////////////////////////////////////////////////////////////////////////////////////
// 10-Nov-2013
//
//  14CUX RPM Table Simulator (dhb)
//
//  This program simulates (I hope) the block of 6803U4 assembly language code shown below.
//  The code is from tune R3526 (a.k.a R3360A) so the addresses will not match up to some 
//  other tunes, such as Griffith tunes.
//
//  Besides adjusting the RPM brackets, it is important to adjust the 3rd and 4th columns to
//  create a smooth "monotonic function". This program provides a way to test the table by
//  scanning through the RPM range and producing a graphable output file.
//
///////////////////////////////////////////////////////////////////////////////////////////////////

/*
---------------------------------------------------------------------------------------------------
EADB				LEADB:
EADB : CE C8 00			ldx		#$C800		; Location of engine speed table
EADE : 86 0F			ldaa	#$0F		; load length of data table
EAE0 : 97 CA			staa	X00CA		; store $0F into 00CA (general purpose var)
EAE2				LEAE2:					; * Start Loop *
EAE2 : EC 00			ldd		$00,x		; value from C800 table (1st value is $0553 or 5502 RPM)
EAE4 : 93 7A			subd	X007A		; subtract 16-bit instantaneous ignition period
EAE6 : 24 0D			bcc		LEAF5		; branch out if period is LT table value (RPM is higher)
EAE8 : C6 04			ldab	#$04		; add 04 to index
EAEA : 3A			    abx					; add B ($04) to X ($C800) = $C804
EAEB : 7A 00 CA			dec		X00CA		; decrement table length counter
EAEE : 2A F2			bpl		LEAE2		; *  End  Loop * (loop back if not end of table)
EAF0 : 7F 00 5C			clr		X005C		; set fuel map eng spd index to zero
EAF3 : 20 2A			bra		LEB1F		; table ran out, branch way down
EAF5				LEAF5:
EAF5 : DD C8			std		X00C8		; 00C8/C9 is table entry minus current ignition period
EAF7 : 96 CA			ldaa	X00CA		; 00CA is table entry counter ($F->0) and it becomes
EAF9 : 48			    asla				;   the fuel map column index which is the upper 
EAFA : 48			    asla				;   nibble of X005C
EAFB : 48			    asla
EAFC : 48			    asla
EAFD : 97 CA			staa	X00CA		; index shifted to upper nibble
EAFF : A6 02			ldaa	$02,x		; load value from table column 3 ($40, $00 or $80)
EB01 : 2A 08			bpl		LEB0B		; bra if value is not $80
EB03 : DC C8			ldd		X00C8		; value is $80, reload speed delta from above
EB05 : 04			    lsrd
EB06 : 04			    lsrd
EB07 : 04			    lsrd
EB08 : 04			    lsrd				; shift speed delta down to lower nibble
EB09 : 20 0A			bra		LEB15
EB0B				LEB0B:					; value is $40 or $00
EB0B : 85 40			bita	#$40		; test bit 6
EB0D : 27 04			beq		LEB13
EB0F : D6 C8			ldab	X00C8		; value is $40, reload MSB of speed delta from above (no shift)
EB11 : 20 02			bra		LEB15
EB13				LEB13:					; value is $00
EB13 : D6 C9			ldab	X00C9		; reload just the low byte of speed delta (no shift)
EB15				LEB15:
EB15 : A6 03			ldaa	$03,x		; load right-most value from table
EB17 : 3D			    mul					; mpy A (table value) by B (speed delta)
EB18 : 9A CA			oraa	X00CA		; or it into the low nibble of the column index
EB1A : 97 5C			staa	X005C		; <-- store the fuel map column index here

EB1C : BD D4 03			jsr		LD403		; road speed test, reloads X2012 in B before returning
EB1F				LEB1F:
---------------------------------------------------------------------------------------------------
*/

#include <stdio.h>

typedef   signed char  CHAR;
typedef unsigned char  UCHAR;
typedef unsigned short UINT16;

// endian swap macro
#define USHORT_BE2LE(x) ((((x) & 0x00FF) << 8) | (((x) & 0xFF00) >> 8))

#define A 1     // these are reversed due to the endian issue
#define B 0

#define C8 1    // (ditto)
#define C9 0


// The A and B accumulators can be used as separate 8-bit registers
// or together as a 16-bit register. A union is perfect for modelling this.
// X00C8 and X00C9 are used in a similar way
union ABunion
{
   UINT16 ab16;
   UCHAR  ab8[2];
};


// There are 4 RPM table examples here
// 0 = Standard Land Rover Table (5502 RPM)
// 1 = Std LR with only RPM brackets spread to 6200 RPM
// 2 = Same as 1 but with 4th col values modified
// 3 = RPM table from aftermarket chip (6000 RPM)

#define RPM_TABLE 3     // <<--- SELECT A TABLE HERE


#if RPM_TABLE == 0

static UCHAR rpmTable[64] = {   // Standard L-R Table

	0x05, 0x53, 0x40, 0x00,     // 5502 RPM    Delta
	0x06, 0x2A, 0x00, 0x13,	    // 4753 RPM     749
	0x07, 0x25, 0x00, 0x10,   	// 4100 RPM     653
	0x07, 0xD0, 0x00, 0x18,	    // 3750 RPM     350
    0x09, 0x73, 0x80, 0x9C,	    // 3100 RPM     650
    0x0A, 0xD9, 0x80, 0xB7,	    // 2700 RPM     400
    0x0E, 0xA6, 0x80, 0x43,	    // 2000 RPM     700
    0x10, 0xBD, 0x80, 0x7A,	    // 1750 RPM     250
    0x14, 0xED, 0x80, 0x3D,	    // 1400 RPM     350
    0x1A, 0xA2, 0x80, 0x2C,	    // 1100 RPM     300
    0x20, 0x8D, 0x80, 0x2B,	    //  900 RPM     200 
    0x25, 0x8F, 0x80, 0x33,	    //  780 RPM     120
    0x29, 0xDA, 0x80, 0x3B,	    //  700 RPM      80
    0x2F, 0x40, 0x80, 0x2F,	    //  620 RPM      80
    0x3D, 0x09, 0x80, 0x12,	    //  480 RPM     140
    0x92, 0x7C, 0x40, 0x2F		//  200 RPM     280
};
#endif

#if RPM_TABLE == 1

static UCHAR rpmTable[64] = {   // L-R Table modified to 6200 (no changes to 3rd & 4th cols)

	0x04, 0xB9, 0x40, 0x00,     // 6200 RPM    Delta
	0x05, 0xBE, 0x00, 0x13,	    // 5100 RPM    1100
	0x06, 0xA8, 0x00, 0x10,   	// 4400 RPM     700
	0x07, 0x9C, 0x00, 0x18,	    // 3850 RPM     550
    0x08, 0x9A, 0x80, 0x9C,	    // 3405 RPM     445
    0x0A, 0x76, 0x80, 0xB7,	    // 2800 RPM     605
    0x0D, 0xF3, 0x80, 0x43,	    // 2100 RPM     700
    0x10, 0xBD, 0x80, 0x7A,	    // 1750 RPM     350
    0x14, 0xED, 0x80, 0x3D,	    // 1400 RPM     350
    0x1A, 0xA2, 0x80, 0x2C,	    // 1100 RPM     300
    0x20, 0x8D, 0x80, 0x2B,	    //  900 RPM     200 
    0x25, 0x8F, 0x80, 0x33,	    //  780 RPM     120
    0x29, 0xDA, 0x80, 0x3B,	    //  700 RPM      80
    0x2F, 0x40, 0x80, 0x2F,	    //  620 RPM      80
    0x3D, 0x09, 0x80, 0x12,	    //  480 RPM     140
    0x92, 0x7C, 0x40, 0x2F		//  200 RPM     280
};
#endif

#if RPM_TABLE == 2

static UCHAR rpmTable[64] = {   // Above 6200 table with smoothing changes

	0x04, 0xB9, 0x40, 0x00,     // 6200 RPM    Delta
	0x05, 0xBE, 0x00, 0x12,	    // 5100 RPM    1100
	0x06, 0xA8, 0x00, 0x11,   	// 4400 RPM     700
	0x07, 0x9C, 0x00, 0x10,	    // 3850 RPM     550
    0x08, 0x9A, 0x80, 0xF6,	    // 3405 RPM     445
    0x0A, 0x76, 0x80, 0x7F,	    // 2800 RPM     605
    0x0D, 0xF3, 0x80, 0x48,	    // 2100 RPM     700
    0x10, 0xBD, 0x80, 0x60,	    // 1750 RPM     350
    0x14, 0xED, 0x80, 0x3D,	    // 1400 RPM     350
    0x1A, 0xA2, 0x80, 0x2C,	    // 1100 RPM     300
    0x20, 0x8D, 0x80, 0x2B,	    //  900 RPM     200
    0x25, 0x8F, 0x80, 0x33,	    //  780 RPM     120
    0x29, 0xDA, 0x80, 0x3B,	    //  700 RPM      80
    0x2F, 0x40, 0x80, 0x2F,	    //  620 RPM      80
    0x3D, 0x09, 0x80, 0x12,	    //  480 RPM     140
    0x92, 0x7C, 0x40, 0x2F		//  200 RPM     280
};
#endif

#if RPM_TABLE == 3

static UCHAR rpmTable[64] = {   // an aftermarket tune
    0x04, 0xE2, 0x40, 0x00,     // 6000 RPM
    0x05, 0x94, 0x00, 0x13,	    
    0x06, 0x82, 0x00, 0x10,
    0x07, 0xD0, 0x00, 0x18,	    
    0x09, 0xC4, 0x80, 0x9C,
    0x0B, 0xB8, 0x80, 0xB7,	    
    0x0E, 0xA6, 0x80, 0x43,
    0x10, 0xBD, 0x80, 0x7A,	    
    0x14, 0xED, 0x80, 0x3D,
    0x1A, 0xA2, 0x80, 0x2C,	    
    0x20, 0x8D, 0x80, 0x2B,
    0x25, 0x8F, 0x80, 0x33,	    
    0x29, 0xDA, 0x80, 0x3B,
    0x2F, 0x40, 0x80, 0x2F,	    
    0x3D, 0x09, 0x80, 0x12,
    0x92, 0x7C, 0x40, 0x2F	    
};
#endif



///////////////////////////////////////////////////////////////////////////////////////////////////
// 
// This function is a model of the 14CUX RPM to Fuel Map Row Index transfer function.
//
// It returns the 8-bit row index into the fuel map for a given spark period (2 uSec units).
// It also returns (by pointer) the fuel map bracket value. If the RPM table is not correct,
// the bracket value may differ from the upper nibble of the row index.
//
///////////////////////////////////////////////////////////////////////////////////////////////////
UCHAR getColumnIndex (UINT16 X007A, UCHAR *bracket)
{

    ABunion regs, C8C9;                         // union defined above
    UCHAR  X005C;                               // the column index to be returned

    UCHAR *tablePtr = rpmTable;                 // ldx  #$C800
    CHAR X00CA = 0x0F;                          // ldaa #$0F, staa	X00CA

LEAE2:
    regs.ab16 = *(UINT16 *)tablePtr;            // ldd	$00,x
    regs.ab16 = USHORT_BE2LE(regs.ab16);        // oh yes, don't forget the endian issue
    if (regs.ab16 >= X007A) {                   // if table value >= period ...
        regs.ab16 -= X007A;                     // subd	X007A (subtract period)
        goto LEAF5;                             // carry bit is clear, branch to process remainder
    }
    regs.ab16 -= X007A;                         // subd X007A
    tablePtr += 4;                              // ldab #$04, abx
    X00CA--;                                    // dec  X00CA
    if (X00CA >= 0)                             // bpl	LEAE2 (branch back if pos value)
        goto LEAE2;

    X005C = 0;                                  // clr X005C (RPM lower than 200)
    goto LEB1F;                                 // LEB1F = return (0)

    if (X00CA == 0) {                           // if code fell through to here, RPM is < 200
        X005C = 0x00;                           // so set the col index to zero and return
        return X005C;
    }
    
LEAF5:                                      // if here, loop terminated before end of table
    C8C9.ab16 = regs.ab16;                  // std	X00C8 (store remainder)
    regs.ab8[A] = X00CA;                    // ldaa	X00CA
    regs.ab8[A] = regs.ab8[A] << 4;         // 4 * alsa (table row becomes upper nibble)
    X00CA = regs.ab8[A];                    // staa	X00CA
    *bracket = X00CA;                       // this is also the bracket value to be returned
    regs.ab8[A] = *(tablePtr + 2);          // ldaa	$02,x (control byte from 3rd column)

    if (!(regs.ab8[A] & (1 << 7)))          // bpl	LEB0B (test sign bit for value 0x80)
        goto LEB0B;                         // branch if not 0x80

    regs.ab16 = C8C9.ab16;                  // value is 0x80, reload speed delta (remainder)
    regs.ab16 = regs.ab16 >> 4;             // 4 * lsrd (use high byte)
    goto LEB15;

LEB0B:
    if (!(regs.ab8[A] & (1 << 6)))          // bita	#$40 (test bit 6 for value 0x40)
        goto LEB13;                         // branch if not 0x40

    regs.ab8[B] = C8C9.ab8[C8];             // ldab	X00C8
    goto LEB15;                             // bra	LEB15

LEB13:                                      // control byte is 0x00
    regs.ab8[B] = C8C9.ab8[C9];             // ldab	X00C9 (use low byte)

LEB15:
    regs.ab8[A] = *(tablePtr + 3);          // get the multiplier byte from table (4th column)
    regs.ab16 = regs.ab8[A] * regs.ab8[B];  // multiply A * B (result in AB
    regs.ab8[A] |= X00CA;                   // OR the nibbles
    X005C = regs.ab8[A];                    // the final row index

LEB1F:
	return (X005C);
}


///////////////////////////////////////////////////////////////////////////////////////////////////
//
// This outputs 4 columns to file
//  1) RPM (period is actually passed to the function)
//  2) Bracket value
//  3) The full 8-bit column index value
//  4) Upper nibble of index value (should match bracket if table is correct)
//
//  Output is tab delimited and can be graphed with Excel, Matlab or whatever you have.
//  As mentioned above, a smooth monotonic curve is important.
//
///////////////////////////////////////////////////////////////////////////////////////////////////
int main(void)
{
    FILE *fptr;
    UINT16 period;
    UCHAR colIndex;
    UCHAR bracket;


    fptr = fopen ("rowIndexCurve.txt", "wt");

    if (!fptr)
        printf("Could not open file for writing\n");


    for (UINT16 rpm = 120; rpm < 6500; rpm += 10) {

        bracket = 0;

        period = (UINT16)(7500000.0/rpm);

        colIndex = getColumnIndex(period, &bracket);

        if (fptr)
            fprintf(fptr, "%5u \t 0x%02X \t %3u \t %3u\n", rpm, bracket, colIndex, (colIndex & 0xF0));

    }
}

