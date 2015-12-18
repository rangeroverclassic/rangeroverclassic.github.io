;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:    RPM Table
;
;   This table sets up the RPM brackets for the fuel map. Ignition period is
;   measured by the microprocessor and stored as a 16-bit number. The period
;   is measured in 1 uSec increments but is divided by 2 and stored in 2 uSec
;   units. The first two columns in the table are the 16-bit ignition period
;   brackets and the right two columns tell the software how to interpolate
;   the remainder.
;
;   If editing this table, it's important to make sure that the interpolation
;   values are correct for a smoothly changing curve.
;
;------------------------------------------------------------------------------

*               =           $C800

rpmTable        DB          $05, $53, $40, $00  ; 5502 RPM
                DB          $06, $2A, $00, $13  ; 4753 RPM
                DB          $07, $25, $00, $10  ; 4100 RPM
                DB          $07, $D0, $00, $18  ; 3750 RPM
                DB          $09, $73, $80, $9C  ; 3100 RPM
                DB          $0A, $D9, $80, $B7  ; 2700 RPM
                DB          $0E, $A6, $80, $43  ; 2000 RPM
                DB          $10, $BD, $80, $7A  ; 1750 RPM
                DB          $14, $ED, $80, $3D  ; 1400 RPM
                DB          $1A, $A2, $80, $2C  ; 1100 RPM
                DB          $20, $8D, $80, $2B  ;  900 RPM
                DB          $25, $8F, $80, $33  ;  780 RPM
                DB          $29, $DA, $80, $3B  ;  700 RPM
                DB          $2F, $40, $80, $2F  ;  620 RPM
                DB          $3D, $09, $80, $12  ;  480 RPM
                DB          $92, $7C, $40, $2F  ;  200 RPM
