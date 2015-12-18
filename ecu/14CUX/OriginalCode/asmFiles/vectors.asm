;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:    6803U4 Vectors and Other End-of-PROM Data
;
;   This file contains the microprocessor's vector table, the tune number and
;   the checksum fixer byte. In addition, some now unused values are stored
;   here (CRC16 and TUNE_IDENT). The unused area between the end of active
;   code and the beginning of this data is filled using the DS psuedo-op.
;
;------------------------------------------------------------------------------


                DS          $FFE0-*,$FF         ; fill from wherever we left off at the
                                                ; end of the code section

*               =           $FFE0               ; The positions of the data/vectors at the
                                                ; end of the ROM are fixed, so set the PC
                                                ; explicitly here.
                                                
                DW          CRC16               ; unused, no need to update
                
                DW          $FFFF, $FFFF, $FFFF

*               =           $FFE8               ; this location is important

                DB          $00                 ; unknown; usually $00
                DW          TUNE_NUMBER
                DB          CHECKSUM_FIXER
                DW          TUNE_IDENT
                DW          reset               ; unused vector?

                DW          purgeValveInt
                DW          purgeValveInt
                DW          purgeValveInt
                DW          inputCapInt

                DW          nmiInterrupt
                DW          purgeValveInt
                DW          nmiInterrupt
                DW          reset

