; shared.inc - EASM constants shared by both cartridge pages: key codes, RAM layout, page selectors,
; firmware addresses, error numbers, page-2 jump-table slots.
; Copyright (C) 2026 Santiago Crespo
; SPDX-License-Identifier: 0BSD

CR = 13
LF = 10
ESC = 27
BS = 8
TAB = 9
DEL = 0x7F
LEFT = 136			; key codes (as in EBASIC)
RIGHT = 137
DOWN = 138
UP = 139
HOME = 140			; ALT+LEFT / ALT+RIGHT
END = 141
HELP = 142			; SHIFT+HELP is TAB
MAXLEN = 250			; characters in a source line

PAGE1 = 0x80			; port 0x03: first 16 KiB of the cartridge (EASM)
PAGE2 = 0x83			; second 16 KiB (guide): bit 1 selects it on the RevD board, bit 0 in MAME

; Firmware RAM, used only to run its interrupt routine as a timer and cursor service (see EBASIC)
FW_KEYST = 0xDB00		; D0 = "key pending": the ISR then skips its keyboard scan and idle power-off
FW_KEYCODE = 0xDB01		; must not be B4 (OFF) while FW_KEYST = D0
FW_DIRTY = 0xDCF0		; 4 row-dirty flags, then cursor column, row, style, enable
FW_HOOK = 0xDFF5

;---------------------------------------------------------------- RAM (C000-DAFF; DB00-DFFF is the firmware's)
LBUF = 0xC000			; 256: the line being edited (editor, command line); page aligned
VARS = 0xC100			; 256: variables
WBUF = 0xC200			; 256: assembler line, guide page text; page aligned
ROWBUF = WBUF+0x80		; 81: a screen being built (viewers)
RAMCODE = 0xC300		; trampolines and interrupt hook (copied from ROM)
SCRSAVE = 0xC380		; 80: the console while a viewer or the guide covers it
HLINES = 0xC3D0			; 40: start/end of each line of a guide page
STACK = 0xC500			; initial SP; the stack (C400-C4FF) is shared with user programs
SRCBEG = 0xC500			; source text, then the symbol table, up to SRCLIM
SRCLIM = 0xD000
USRBEG = 0xD000			; user RAM: the only memory EASM writes code or data into
USREND = 0xDAFF			; (last byte)

SCR = VARS			; 80-byte shadow screen
CX = SCR+80
CY = CX+1
CAPS = CY+1
P12 = CAPS+1			; last value written to port 0x12
RELCNT = P12+1
LASTSC = RELCNT+1
REPCNT = LASTSC+1
OFFARM = REPCNT+1
ISRON = OFFARM+1		; the firmware ISR is enabled
RUNNING = ISRON+1		; a user program runs (ANSWER breaks it)
CURSOFF = RUNNING+1		; no cursor while waiting for a key
; editor
TXTEND = CURSOFF+1		; end of the source text (first free byte)
NLINES = TXTEND+2		; number of lines (at least 1)
CURL = NLINES+2			; line being edited (0-based)
TOPL = CURL+2			; line on the top row
CUR = TOPL+2			; cursor in LBUF
LEN = CUR+1			; length of LBUF
HOFS = LEN+1			; first character of LBUF shown
MODIF = HOFS+1			; LBUF differs from the stored line
NUMSHOW = MODIF+1		; line numbers on the left
LINEPTR = NUMSHOW+1		; scratch
; assembler
PC = LINEPTR+2			; address of the statement being assembled (ASMB reads it)
PASS = PC+2			; 1 or 2
ASMLN = PASS+1			; line being assembled (0-based)
ENTRY = ASMLN+2			; entry point (END operand, else the first byte)
ENTOK = ENTRY+2			; 0: none, 1: first byte, 2: END operand
LOADR = ENTOK+1			; lowest and highest address written
HIADR = LOADR+2
SYMEND = HIADR+2		; end of the symbol table (it starts at TXTEND)
SYMOK = SYMEND+2		; the table belongs to the current text
UNDEF = SYMOK+1			; an expression used an undefined symbol (pass 1)
RADIX = UNDEF+1			; 10 in the source, 16 in the monitor
INASM = RADIX+1			; errors name the line
ERRSP = INASM+1			; error recovery: stack pointer and handler
ERRJP = ERRSP+2
ERRNO = ERRJP+2			; last error, its line (+1, 0: none) and column
ERRLN = ERRNO+1
ERRCOL = ERRLN+2
LABPOS = ERRCOL+1		; scratch for the line parser
OBUF = LABPOS+2			; 8: code of one instruction
; monitor
GOSP = OBUF+8			; stack pointer at G
REGS = GOSP+2			; AF BC DE HL IX IY SP PC at the end of the last program
REGOK = REGS+16			; 0: none, 1: RET, 2: EXIT, 3: break
MADDR = REGOK+1
HIST = MADDR+2			; 16 addresses: the disassembler goes back through them
HISTN = HIST+32
DLEN = HISTN+1			; length of the instruction just disassembled
DPTR = DLEN+1			; disassembler: address, start, prefix, displacement, opcode, flags
DSTART = DPTR+2
DPFX = DSTART+2
DDISP = DPFX+1
DOP = DDISP+1
DSUB = DOP+1
DCB = DSUB+1
DNOHX = DCB+1
; guide
HSEL = DNOHX+1
HTOP = HSEL+1
HLINE = HTOP+1
HLEN = HLINE+1
HNL = HLEN+1
HEX = HNL+1			; offset of the example (0: none)
HCTX = HEX+2			; caller: 0 editor, 1 command line
NAMBUF = HCTX+1			; 16: a name, length first
ECUR = NAMBUF+16		; editor cursor while the command line is shown
PRUN = ECUR+1			; the command in LBUF (from an editor key) runs at once
RLCOL = PRUN+1			; first column of the input line
FCOUNT = RLCOL+1		; scratch for commands
FFROM = FCOUNT+2
ENDF = FFROM+2			; END was seen
SPP = ENDF+1			; splice: position, old and new size
SPOLD = SPP+2
SPNEW = SPOLD+2
SAVCXY = SPNEW+2		; CX, CY of the saved console
STPC = SAVCXY+2			; address of the statement ($)
RLMODE = STPC+2			; readline: 0 at the command prompt, 1 in A and E
EXEDIT = RLMODE+1		; the guide's example goes to the editor
VARS_END = EXEDIT+1

; Error numbers (messages in asm.s)
E_RANGE = 1
E_SYNTAX = 2
E_UNDEF = 3
E_DUP = 4
E_NUMBER = 5
E_PAREN = 6
E_USRRAM = 7
E_SYMFULL = 8
E_DIV0 = 9
E_PHASE = 10
E_NAME = 11
E_TXTFULL = 12
E_CMD = 13
E_STRING = 14
E_NOCODE = 15
E_LONG = 16
E_ESC = 17

; Page-2 jump table at 0x8000+4: slot n is at 0x8004+3*n
S_HELP = 0
S_HELPAT = 1
