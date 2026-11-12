; uses the API: CLS, SETCUR, PRINTSTR, PRDEC, PRHEX16, PRHEX8, PUTCHAR, NEWLINE, DELAY, GETKEY, EXIT
        ORG USERRAM
        CALL CLS
        LD DE,0102H
        CALL SETCUR
        LD HL,TXT
        CALL PRINTSTR
        LD HL,12345
        CALL PRDEC
        CALL NEWLINE
        LD HL,0BEEFH
        CALL PRHEX16
        LD A,7EH
        CALL PRHEX8
        LD A,'!'
        CALL PUTCHAR
        LD HL,100
        CALL DELAY
        CALL GETKEY
        LD (KEY),A
        LD BC,1234H
        CALL EXIT
        RET
TXT:    DB "N=",0
KEY:    DB 0
