;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       Contains equates for hardware registers including MPU, ADC and PAL.
;
;------------------------------------------------------------------------------


; 6803U4 registers are from $0000 through $001F

port1ddr        EQU         $00
port2ddr        EQU         $01
port1data       EQU         $02
port2data       EQU         $03
port3ddr        EQU         $04
port4ddr        EQU         $05
port3data       EQU         $06
port4data       EQU         $07

timerCSR        EQU         $08
counterHigh     EQU         $09
counterLow      EQU         $0A
ocr1High        EQU         $0B
ocr1Low         EQU         $0C
icrHigh         EQU         $0D
icrLow          EQU         $0E
port3csr        EQU         $0F

sciModeControl  EQU         $10
sciTRCS         EQU         $11
sciRxData       EQU         $12
sciTxData       EQU         $13
ramControl      EQU         $14
altCounterHigh  EQU         $15
altCounterLow   EQU         $16
timerCntrlReg1  EQU         $17

timerCntrlReg2  EQU         $18
timerStsReg     EQU         $19
ocr2high        EQU         $1A
ocr2low         EQU         $1B
ocr3high        EQU         $1C
ocr3low         EQU         $1D
icr2high        EQU         $1E
icr2low         EQU         $1F


; PAL register (2 of 4 discrete outputs are used for I2C)

i2cPort         EQU         $4004


; Hitachi Analog-to-Digital Converter (HD46508)

AdcControlReg0  EQU         $6000
AdcControlReg1  EQU         $6001
AdcStsDataHigh  EQU         $6002
AdcDataLow      EQU         $6003
AdcPcDataReg    EQU         $6004

