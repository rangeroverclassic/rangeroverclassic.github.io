;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:    RAM Variables
;
;   There are two areas of RAM.
;
;   MPU: $0040 to $00FF  (192 bytes)
;   PAL: $2000 to $20FF  (128 bytes)
;
;   Of the MPU's 192 bytes of RAM, the first 32 bytes are battery-backed or
;   preserved using a small amount of battery current. Of these 32 bytes, only
;   the first 20 bytes are actually used in this way, the remainder is treated
;   like normal RAM and cleared to zero on startup.
;
;   It should be noted that the MPU internal memory is actually faster than
;   the external PAL memory. This is because the internal memory can be
;   accessed using direct addressing instead of extended addressing. See the
;   Motorola documentation for more info on this.
;
;------------------------------------------------------------------------------

batteryBackedRAM    = $0040
externalRAMCopy     = $2060
sizeOfRAMBackup     = $0013

secondaryLambdaR    = $0040 ; used during lambda calculations
longLambdaTrimR     = $0042 ; read by RoverGauge as the diagnostic value
secondaryLambdaL    = $0044
longLambdaTrimL     = $0046
hiFuelTemperature   = $0048
faultBits_49        = $0049
faultBits_4A        = $004A
faultBits_4B        = $004B
faultBits_4C        = $004C
faultBits_4D        = $004D
faultBits_4E        = $004E
fuelMapNumberBackup = $0050
throttlePotMinimum  = $0051
throttlePotMinCopy  = $0053
ramChecksum         = $0053 ; note that this location is used twice
mainVoltageAdj      = $0055
mafDirectLo         = $0057
mafDirectHi         = $0059
fuelMapLoadIdx      = $005B
fuelMapSpeedIdx     = $005C
throttlePot         = $005F
o2ReferenceSense    = $0064
shortLambdaTrimR    = $0065
shortLambdaTrimL    = $0067
tmpFaultCodeStorage = shortLambdaTrimL ; used for fault code storage only during startup
coolantTempCount    = $006A
coolantTempAdjust   = $006B
iacPosition         = $006D
iacMotorStepCount   = $0075
adcMuxTablePtr      = $0076
adcMuxTableStart    = $0078
ignPeriod           = $007A
ignPeriodFiltered   = $007C
engineRPM           = $007E
compedFuelingVal    = $0082
purgeValveTimer     = $0096
fuelPumpTimer       = $00AF
rsFaultSlowdown     = $00BB
neutralSwitchVal    = $2000
roadSpeed           = $2003
fuelTempCount       = $2006
rpmLimitRAM         = $200C
fuelMapPtr          = $2026
fuelMapNumber       = $202C
faultSlowDownCount  = $2030
IF BUILD_R3383
startupDownCount1Hz = $205F
ELSE
startupDownCount1Hz = $2039 ; initialized to 12 and counts down to 0
ENDC
romChecksum         = $2041
mafLinear           = $204D
targetIdleRPM       = $2051
romChecksumMirror   = $2069
tpFaultSlowdown     = $2077

