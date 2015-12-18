@ECHO OFF
SETLOCAL
IF NOT EXIST diffs MKDIR diffs
SET KEY=
IF "%1" == ""  GOTO START
SET KEY=%1
GOTO CHOICE

-------------------------------------------------------------------------------------
NOTE:
The intent of this batch file is to duplicate the original Land-Rover or TVR code
and do a successful binary comparison with the original code. The old DOS file
comparison utility (FC) is used and the reference binaries are in the subdirectoty
'Reference_Bins'. The user should check the diffs file after code is built in order
to confirm a successful rebuild. Here are the steps involved:

1. Open a Windows console using 'cmd'.
2. CD into directory where batch file is located (OriginalCode).
3. Run 'build' and input choice.
4. Batch file takes user input and copies 'data_Rxxx.asm' to 'data.asm'.
5. Crasm assembler is called to assemble 'crasm_main.asm' which lists all files to
   be included in the build. Order is important!!
6. Crasm outputs Motorola S-Record format, so 'srec2bin' converts it to binary.
7. File compare utility is used to output differences to 'Rxxxx_diffs.txt'.
   (It should say "FC: no differences encountered")
8. Finalize utility fixes the checksum and stacks code to 32K.
-------------------------------------------------------------------------------------

:START
ECHO.
ECHO Please select a 14CUX tune version to build...
ECHO 0. R3360     (94 RRC/Disco 3.9 NAS)
ECHO 1. R3361     (94 RRC 4.2 NAS)
ECHO 2. R3365     (94 D90 NAS)
ECHO 3. R3383     (94 RRC UK)
ECHO 4. R3526     (95 RRC NAS)
ECHO 5. R3652     (NAS Cold weather upgrade)
ECHO 6. R2967_55  (94 Griffith)
ECHO 7. R2967_5B  (95 Griffith)
ECHO 8. R2967_9B  (Chimaera 400)
ECHO 9. R2967_E0  (Chimaera 450)
ECHO.
ECHO Q TO QUIT
SET /P KEY=

:CHOICE
IF '%KEY%' == '0' GOTO R3360
IF '%KEY%' == '1' GOTO R3361
IF '%KEY%' == '2' GOTO R3365
IF '%KEY%' == '3' GOTO R3383
IF '%KEY%' == '4' GOTO R3526
IF '%KEY%' == '5' GOTO R3652
IF '%KEY%' == '6' GOTO R2967_55
IF '%KEY%' == '7' GOTO R2967_5B
IF '%KEY%' == '8' GOTO R2967_9B
IF '%KEY%' == '9' GOTO R2967_E0
IF '%KEY%' == 'q' GOTO END
IF '%KEY%' == 'Q' GOTO END
GOTO START

:R3360
cd asmFiles
COPY /Y data_R3360.asm data.asm
..\tools\crasm_1.7 -o ..\temp.srec -l -x crasm_main.asm > ..\crasm_log.txt
cd ..
tools\srec2bin -o 0xC000 temp.srec R3360.bin
FC /b R3360.bin Reference_Bins\R3360.bin > diffs\R3360_diffs.txt
tools\finalize -d R3360.bin
GOTO END

:R3361
cd asmFiles
COPY /Y data_R3361.asm data.asm
..\tools\crasm_1.7 -o ..\temp.srec -l -x crasm_main.asm > ..\crasm_log.txt
cd ..
tools\srec2bin -o 0xC000 temp.srec R3361.bin
FC /b R3361.bin Reference_Bins\R3361.bin > diffs\R3361_diffs.txt
tools\finalize -d R3361.bin
GOTO END

:R3365
cd asmFiles
COPY /Y data_R3365.asm data.asm
..\tools\crasm_1.7 -o ..\temp.srec -l -x crasm_main.asm > ..\crasm_log.txt
cd ..
tools\srec2bin -o 0xC000 temp.srec R3365.bin
FC /b R3365.bin Reference_Bins\R3365.bin > diffs\R3365_diffs.txt
tools\finalize -d R3365.bin
GOTO END

:R3383
cd asmFiles
COPY /Y data_R3383.asm data.asm
..\tools\crasm_1.7 -o ..\temp.srec -l -x crasm_main.asm > ..\crasm_log.txt
cd ..
tools\srec2bin -o 0xC000 temp.srec R3383.bin
FC /b R3383.bin Reference_Bins\R3383.bin > diffs\R3383_diffs.txt
tools\finalize -d R3383.bin
GOTO END


:R3526
cd asmFiles
COPY /Y data_R3526.asm data.asm
..\tools\crasm_1.7 -o ..\temp.srec -l -x crasm_main.asm > ..\crasm_log.txt
cd ..
tools\srec2bin -o 0xC000 temp.srec R3526.bin
FC /b R3526.bin Reference_Bins\R3526.bin > diffs\R3526_diffs.txt
tools\finalize -d R3526.bin
GOTO END


:R3652
cd asmFiles
COPY /Y data_R3652.asm data.asm
..\tools\crasm_1.7 -o ..\temp.srec -l -x crasm_main.asm > ..\crasm_log.txt
cd ..
tools\srec2bin -o 0xC000 temp.srec R3652.bin
FC /b R3652.bin Reference_Bins\R3652.bin > diffs\R3652_diffs.txt
tools\finalize -d R3652.bin
GOTO END


:R2967_55
cd asmFiles
COPY /Y data_R2967_55.asm data.asm
..\tools\crasm_1.7 -o ..\temp.srec -l -x crasm_main.asm > ..\crasm_log.txt
cd ..
tools\srec2bin -o 0xC000 temp.srec R2967_55.bin
FC /b R2967_55.bin Reference_Bins\R2967_55.bin > diffs\R2967_55_diffs.txt
tools\finalize -d R2967_55.bin
GOTO END


:R2967_5B
cd asmFiles
COPY /Y data_R2967_5B.asm data.asm
..\tools\crasm_1.7 -o ..\temp.srec -l -x crasm_main.asm > ..\crasm_log.txt
cd ..
tools\srec2bin -o 0xC000 temp.srec R2967_5B.bin
FC /b R2967_5B.bin Reference_Bins\R2967_5B.bin > diffs\R2967_5B_diffs.txt
tools\finalize -d R2967_5B.bin
GOTO END


:R2967_9B
cd asmFiles
COPY /Y data_R2967_9B.asm data.asm
..\tools\crasm_1.7 -o ..\temp.srec -l -x crasm_main.asm > ..\crasm_log.txt
cd ..
tools\srec2bin -o 0xC000 temp.srec R2967_9B.bin
FC /b R2967_9B.bin Reference_Bins\R2967_9B.bin > diffs\R2967_9B_diffs.txt
tools\finalize -d R2967_9B.bin
GOTO END


:R2967_E0
cd asmFiles
COPY /Y data_R2967_E0.asm data.asm
..\tools\crasm_1.7 -o ..\temp.srec -l -x crasm_main.asm > ..\crasm_log.txt
cd ..
tools\srec2bin -o 0xC000 temp.srec R2967_E0.bin
FC /b R2967_E0.bin Reference_Bins\R2967_E0.bin > diffs\R2967_E0_diffs.txt
tools\finalize -d R2967_E0.bin
GOTO END


:END
ENDLOCAL
ECHO Done!