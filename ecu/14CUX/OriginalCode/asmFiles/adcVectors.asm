;------------------------------------------------------------------------------
;   14CUX Firmware Rebuild Project
;
;   File Date: 14-Nov-2013
;
;   Description:
;       This is a vector table consisting of 16 pointers to service routines.
;   They are indexed by the channel number in the ADC control list. The O2
;   sensors are not in the ADC control list (even for closed loop) because they
;   are measured in the ICI. The "o2sense" vector in this list simply points
;   to an RTS instruction.
;
;------------------------------------------------------------------------------

adcVectors      DW          adcRoutine0         ; Inertia switch
                DW          adcRoutine1         ; Heated screen sense
                DW          adcRoutine2         ; Air flow sensor (main signal)
                DW          adcRoutine3         ; Throttle pot
                DW          adcRoutine4         ; Coolant temp thermistor
                DW          adcRoutine5         ; Auto neutral switch
                DW          adcRoutine6         ; Air cond load input
                DW          adcRoutine7         ; Road speed transducer
                DW          adcRoutine8         ; Main relay voltage
                DW          adcRoutine9         ; Air flow sensor (trim setting)
                DW          adcRoutine10        ; Tune resistor
                DW          adcRoutine11        ; Fuel temp thermistor
                DW          o2sense             ; Right O2 sensor
                DW          adcRoutine13        ; O2 Reference Voltage
                DW          adcRoutine14        ; Diagnostic plug
                DW          o2sense             ; Left O2 sensor

