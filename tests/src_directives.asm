; directives, labels, forward references, expressions
COUNT EQU 3
BASE = 0D100H
        ORG USERRAM
START:  LD B,COUNT
LOOP:   DJNZ LOOP
        JR FWD
        LD HL,TABLE+2
        LD A,(IX+OFS)
        JP FWD2
TABLE:  DB 1,2,'A',"Hi",-1,255
        DW START,1234H,$
        DS 3,0AAH
FWD:    LD A,LOW
FWD2:   RET
OFS     EQU 10-3*2
LOW     EQU (1+2)*4%5|80H
MASK = %1010 & 0x0F ^ 1010B
        LD BC,BASE>>4
        LD DE,~0
        LD A,'Z'-'A'
        LD A,MASK : RET
        END START
