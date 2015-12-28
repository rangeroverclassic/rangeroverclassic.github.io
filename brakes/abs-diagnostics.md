---
layout: page 
title:  "ABS diagnostics"
date:   2015-12-8 00:00:00 -0800
categories: abs brakes diagnostics 
---

From
http://www.rangerovers.net/forum/8-range-rover-classic/25706-rr-91-abs-problem.html

User http://www.rangerovers.net/forum/1026-olmectech.html Re: RR-91 ABS Problem

Below are instructions on how to retreive ABS fault codes for RRC.

Under the RRC's front driver seat in the front is a blue connector used to
connect the ABS testbook equipment.

1. Fabricate a jumper wire with 12 gauge wire about inch long

2. Connect jumper wire to the "black" and "black/pink" pins. Turn ignition
   to position 2.

3. Five seconds after the ignition is turned to position 2 the Anti-Lock
   warning light will extinguish, indicating the start of the cycle.

4. Observe the Anti-Lock warning light, the start phase of the blink code
   is signified by the following:

- Pause = 2.5 secs. (long)
- Flash = 2.5 secs. (long)
- Pause = 2.5 secs. (long)
- Flash = 0.5 secs. (short)

5. The first part of the code number is determined by a pause of 2.5 secs.
which precedes a series of short flashes then a long pause. The number of
short flashes is equal to the first digit in the fault code.

6. The second digit in the code number is determined after a pause of 2.5
secs. which occurs between the first and second code flashes. After the
pause there will be a number of short flashes, the number of flashes is
equal to the second digit in the fault code. After the flashes there will
be another pause of 2.5 seconds before the system repeats the flash and
pause sequence. This will allow for a verification of the code or if the
initial flash and pause sequence was missed.

7. The sequence of the start phase, first and second code parts will
continue until terminated by the operator. To terminate the code sequence
disconnect the jumper wire.

NOTE:Termination will clear the memory of that particular fault, and the
fault will not be retrievable. Do not terminate the sequence if unsure of
the code number.

8. The memory is capable of storing more than one fault. To search the
memory, after the jumper wire is disconnected wait until the Anti-Lock
light illuminates and then turn the ignition off, the code is now
completely cleared. To obtain the next code repeat the procedure from step
2.

9. If there are no faults remaining there will be a long pause of 7.5 secs.
after the start phase.

10. Once all the codes have been obtained and cleared, locate the problem
cause and rectification for each code and fix accordingly.


**FAULT CODE LIST**

**KEY:** **IV** - Inlet Valve, **OV** - Outlet Value, **RCP** - Recirculation pump (ABS
pump)

Sensor check:

1. Carry out multimeter test, check electrical resistance of sensor, this
should be 700-2000 ohms. Check sensor voltage output, this should be
greater than or equal to 0.93 VAC RMS when rotating the wheel at 1 rev/sec.

2. Check sensor air gap. Push sensor through bush until it touches exciter
ring. Sensor will be knocked back to correct position when the vehicle is
driven.

3. Check run out of the exciter ring and rectify if necessary.

4. Check bearing play and adjust if necessary.

5. Check sensor bush and exchange if necessary.

#### The Codes: 

* Code 2-6 - Faulty stoplight switch or wiring. Fuse A5 blown or
not fitted 
* Code 2-7 - Continuous supply to ECU with ignition off. Faulty valve relay or wiring 
* Code 2-8 - No voltage to ABS solenoid valves. Faulty
valve relay or wiring.  
* Code 2-12 - Front right, too large an air gap or
the sensor has been forced out by exciter ring.  
* Code 2-13 - Rear left, too
large an air gap or the sensor has been forced out by exciter ring.  
* Code
2-14 - Front left, too large an air gap or the sensor has been forced out
by exciter ring.  
* Code 2-15 - Rear right, too large an air gap or the
sensor has been forced out by exciter ring.  
* Code 3-0 to 3-9 - Open circuit
in connection from ECU to solenoid valve in booster, or in ECU 
* Code 4-0 to
4-9 - Short circuit to earth in connection from ECU to solenoid valve in
booster 
* Code 4-12 - Front right, wiring to sensor broken or sensor
resistance too high.  
* Code 4-13 - Rear left, wiring to sensor broken or
sensor resistance too high.  
* Code 4-14 - Front left, wiring to sensor
broken or sensor resistance too high. 
* Code 4-15 - Rear right, wiring to
sensor broken or sensor resistance too high.  
* Code 5-0 to 5-9 - Short
circuit to 12volt in connection from ECU to solenoid valve in booster,
possible earth fault.
* Code 5-12 - Front right, intermittent fault with
sensor or wiring 
* Code 5-13 - Rear left, intermittent fault with sensor or
wiring 
* Code 5-14 - Front left, intermittent fault with sensor or wiring

* Code 5-15 - Rear right, intermittent fault with sensor or wiring 
* Code 6-0
to 6-9 - Short circuit between two connection from ECU to solenoid valve in
booster.  
* Code 6-12 - Front right, no output from sensor, sensor may have
too large an air gap.  
* Code 6-13 - Rear left, no output from sensor, sensor
may have too large an air gap.  
* Code 6-14 - Front left, no output from
sensor, sensor may have too large an air gap.  
* Code 6-15 - Rear right, no
output from sensor, sensor may have too large an air gap. 

---

#### OCR of RAVE manual:

FAULT DIAGNOSIS PROCEDURE If diagnostic equipment is not available the
following procedure can be carried out using the 'Blink Code' and
a multi-meter. Faults are stored in the ECU memory in code form. The
information can be retrieved by initiating and reading a series of flash and
pause sequences on the ABS warning light.  Use of the blink code will determine
the location of the fault prior to carrying out a multi-meter check, thus
reducing multi-meter checking time.  Additionally the blink code can be used
exclusively where a fault has occurred, and no other diagnostic equipment is
available.


Recommended equipment

A female plug to fit the diagnostic plug, prewired to connect ECU pin 14 to
earth by bridging the black/pink and black diagnostic plug wires.  To initiate
the blink code carry out the following procedure:

1. Switch off ignition.

2. Remove the seat side trim to gain access to the ECU and relays, and on early
vehicles the diagnostic plug. Unclip the access plate from the seat base front
trim panel. Pull the blue diagnistic plug from its clip through the opening.
Note that the diagnostic plug and fuse condition on early vehicles is shown in
RR2742M.


3. Remove the ABS warning light relay.


4. Switch on ignition, ABS warning light will illuminate.


5. Connect the prewired plug to the diagnostic plug.


6. Five seconds after connecting diagnostic plug the ABS warning light will
extinguish, indicating the start of the blink code cycle.


7. Start phase: Observe the ABS warning light, the start phase consists of:
Pause - 2.5 secs (long) Flash - 2.5 secs (long) Pause - 2.5 secs (long) Flash
- 0.5 secs (short)


8. First part of code number: A pause of 2,5 secs precedes a series of short
flashes. Count the flashes until the next long pause occurs, the number
obtained is the first part of the code number.


9. Second part of code number: A pause of 2.5 secs occurs between first and
second parts, before a second series of short flashes occurs.  The number of
flashes forms the second part of the code number.


10. The sequence of start phase, first and second parts will continue until
terminated by the operator, thus allowing the code obtained to be rechecked.


11. To terminate the sequence disconnect the prewired plug from the diagnostic
plug. Wait for cycle to end before code will clear.  NOTE: Termination will
clear the memory of that particular fault. Do not terminate the sequence if
unsure of the code number.


12. The memory is capable of storing more than one fault. To search the memory,
reconnect the diagnostic plug, and await the next start phase.


13. Repeat procedure until no further faults are stored in the memory. The
memory is cleared when a long pause of 7.5 secs occurs after start phase.


WARNING: Be sure to reconnect the relay after completing test.
