# EASM user's manual

EASM starts by itself when the cartridge is in the Genio and the unit is switched on. The first
screen shows the free bytes for the source text (2815 when it is empty) and the command line:
```
EASM 1.0        2815
Z80 assembler
core: R.T.Russell
>_
```
There are two places to work in: the **editor**, where the program is written, and the **command
line**, where it is assembled and run and where the monitor is. **ANSWER** switches between them.
**HELP** opens the guide anywhere.

## Keys
The key legends are in Spanish; this manual uses English names:

| Name | Key legend | |
|---|---|---|
| ENTER | INTRO | |
| ANSWER | RESPUESTA | editor <-> command line; leaves a viewer or the guide; stops a program |
| HELP | AYUDA | the guide (SHIFT+HELP is TAB) |
| DELETE | REPETIR / BORRAR | deletes to the left |
| DEL | JUGADOR DERECHA / DEL | deletes to the right |
| LEFT, RIGHT | RETROCESO, AVANCE | with ALT: to the start / end of the line |
| up, down | ALT+Ü, ALT+; | previous / next line (in viewers and the guide also Ü and ; alone) |

* CAPS is on at start-up (mnemonics are upper case; EASM accepts either case).
* **SHIFT** gives `¡ ¿ # $ % / & * ( )` on the digits, `? ! " :` on `, . ' ;`, `< >` on LEFT/RIGHT.
* **ALT** gives `\ @ - _ + [ ] =` on 1-8 (the red legends), `|` on 9 and `~` on 0; ALT+vowel an
  accented vowel. PAUSA is `^`.
* **OFF** switches the unit off (the text is lost: the RAM is not kept).

## The editor
```
  LD HL,MESSAGE        every row is a line of the text
  CALL PRINTSTR_       the line with the cursor scrolls sideways when it is long
  RET
MESSAGE:
```
* Type anywhere. DELETE and DEL delete; DELETE in column 0 joins the line to the one above, DEL at
  the end of a line joins the next one.
* **ENTER** splits the line at the cursor. The new line starts with the same indentation; after a
  line with something in column 0 (a label) it starts with two spaces.
* **SHIFT+HELP** (TAB) inserts spaces up to the next column that is a multiple of 4.
* A changed line is stored when the cursor leaves it. Lines are up to 250 characters.
* **HELP** opens the guide at the word under the cursor (a mnemonic or directive), or its index. ENTER
  on a page takes its example: it becomes a new line below the current one.

### Activity panel
The top panel types mnemonics and runs the editor's commands. Down each column:

| Column | Keys (top to bottom) |
|---|---|
| 1 | `LD ` `CALL ` `JP ` `JR ` `RET` |
| 2 | `PUSH ` `POP ` `INC ` `DEC ` `DJNZ ` |
| 3 | `ADD ` `SUB ` `AND ` `OR ` `XOR ` |
| 4 | `CP ` `EX ` `OUT ` `IN ` `(HL)` |
| 5 | `ORG ` `EQU ` `DB ` `DW ` `DS ` |
| 6 | `END`; CINE Y TELEVISION page up; HISTORIA Y GEOGRAFIA page down; GENERAL `LINE ` (go to a line); QUE SOY to the line of the last error |
| 7 | EL NUMERO RELAMPAGO `ASM`; BASIC `RUN`; IMPRIMIR TEXTO the command line; CALCULADORA `? `; CARTUCHOS ADICIONALES `FIND ` |
| 8 | NIVEL line numbers on/off; 1 JUGADOR inserts an empty line above; 2 JUGADORES deletes the line |

On an empty line a mnemonic key indents it first. The keys that end in a space (`LINE `, `? `,
`FIND `) open the command line with that text, ready to complete; ASM and RUN run at once.
2 JUGADORES deletes the line without storing its changes, so it always works, even when the text is full.

## The command line
The screen scrolls like a terminal. A command is typed after `>` and runs with ENTER. Commands:

| Command | |
|---|---|
| `ASM` | assemble the text. Shows `D000-D00B 12 bytes` and `Entry D000`, or an error |
| `RUN` | assemble, then run from the entry point |
| `EDIT [n]`, `LINE n` | the editor, at line n (counting from 1) |
| `FIND text` | the editor at the next line that contains the text (any case), going round |
| `SYM` | the symbols of the last assembly, with their values |
| `? expr` | the value of an expression, in hex and decimal: `? COUNT*2` gives `=0006H 6` |
| `NEW` | erase the text (asks Y/N) |
| `BYE` | back to the Genio's menu |
| `A`, `D`, `M`, `E`, `R`, `G`, `F`, `C` | the monitor (below) |

ANSWER at the prompt goes to the editor.

## Assembly language
```
[label[:]] [instruction or directive] [; comment]
```
* A **label** is a name followed by `:`, or a name in column 0 that is not a mnemonic or directive.
  `name EQU value` (or `name = value`) defines a constant.
* **Names**: up to 15 characters, letters, digits, `_ . ?`, not starting with a digit; upper and lower
  case are the same. Register and condition names (`A`, `B`, `C`, `HL`, `NZ`, ...) cannot be names.
* Several statements on a line are separated by `:` (`LD A,1 : RET`). `;` (or `\`) starts a comment.
* **Instructions**: every official Z80 instruction, in Zilog syntax: `LD A,(IX+5)`, `ADD A,B`,
  `SUB B` (no `A,`), `JP (HL)`, `EX AF,AF'`, `IN A,(10H)`, `OUT (C),A`, `RST 38H`, `IM 1`.
* **Numbers**: `255`, hex `0FFH`, `$FF`, `0xFF`, `&FF`, binary `%1010`, `1010B`, character `'A'` or `"A"`.
  A hex number ending in H must start with a digit: `0FFH` (`FFH` is a name).
* **`$`** alone is the address of the statement.
* **Expressions**, from the strongest: unary `- + ~`; `* / %` (rest) `<< >>`; `+ -`; `&`; `| ^`.
  Parentheses group. Values are 16 bits, wrapping round. Note that an operand that starts with `(` is
  an address in memory: `LD A,(5+3)` reads the byte at 8.
* **Directives**:

| Directive | |
|---|---|
| `ORG addr` | the address of the following code. Before any ORG: 0xD000 |
| `name EQU value` | a constant |
| `DB a,b,"text",...` (`DEFB`, `DEFM`) | bytes: values from -256 to 255, and text |
| `DW a,b,...` (`DEFW`) | 16-bit words, low byte first |
| `DS n[,fill]` (`DEFS`) | n bytes of fill (0) |
| `END [entry]` | the end; RUN and G start at the entry (else at the first byte of code) |

* **Built-in names**: the API entries (below), `USERRAM` (0xD000) and `USEREND` (0xDAFF). A label
  with the same name takes their place.
* **Where code goes**: only into the user RAM, 0xD000-0xDAFF (2816 bytes). Code anywhere else is
  the error "Outside user RAM", so that a program cannot overwrite the text or EASM's own memory.

## Errors
After ASM, an error shows its line number, the line and the message; the QUE SOY key (or `LINE n`)
goes to it in the editor, with the cursor where the error was found.

| Message | Cause |
|---|---|
| Syntax error | not an instruction, wrong operands, or something left at the end of the statement |
| Unknown symbol | a name that is never defined |
| Duplicate label | a name defined twice |
| Out of range | JR/DJNZ too far (-126 to +129), a DB value outside -256..255, a bad RST |
| Bad number | a number with wrong digits (`12Z`, `19H2`) |
| Missing ) | an unclosed parenthesis |
| Bad string | text without its closing quote |
| Division by zero | `/` or `%` by 0 |
| Phase error | a label has another address in pass 2: an `ORG`, `DS` or `EQU` used a name defined later |
| Outside user RAM | code or data outside 0xD000-0xDAFF |
| Name too long | more than 15 characters |
| Symbol table full | the text and its symbols do not fit in 0xC500-0xCFFF |
| Text full | the editor has no room for the line |
| Bad command | an unknown command |
| No code | RUN or G without an entry point |

## The monitor
At the command line. Numbers are **hexadecimal** here (a word made only of hex digits is a number;
other words are symbols: the built-in ones, and those of the last assembly while the text is unchanged); `$` before a number also works. Assembler syntax
applies otherwise.

| Command | |
|---|---|
| `A addr` | assemble one line at a time at addr; the bytes are shown under the line. ENTER alone or ANSWER ends; an error keeps the address |
| `D [addr]` | disassemble four instructions: down one more, up back (through the last 16), RIGHT/LEFT four |
| `M [addr]` | memory, four rows of four bytes: down/up a row, RIGHT/LEFT four rows |
| `E addr [b ...]` | write the bytes; with none, ask for each byte (`D000 3E` then a value; ENTER alone keeps it) |
| `F from,to,byte` | fill |
| `C from,to,with` | compare: the first three differences (`addr old new`), or `Same` |
| `G [addr]` | run (default: the entry point of the last assembly) |
| `R` | the registers when the last program ended |

`D` and `M` without an address continue from the last address used (after RUN or G, the program's start). The viewers leave with ENTER
or ANSWER. Reading works everywhere (0x8000-0xBFFF shows EASM's own first page); **writing (A, E, F,
ASM) only into the user RAM**.

### Running a program
`RUN` and `G` call the program with interrupts on and EASM's first ROM page mapped. It comes back:
* with its last **RET** (the stack must be as it was);
* with **`CALL EXIT`** from anywhere; `R` then shows the registers and the address of the CALL;
* when **ANSWER** is held, if the program has interrupts on: "Break". The registers are not kept then.

The program shares EASM's 256-byte stack (0xC400-0xC4FF): a little under 256 bytes are free for it, and the firmware's interrupt routine also pushes onto it. A program
that disables interrupts and never returns can only be stopped by switching the Genio off and on;
the text is then lost. Before running something risky, write the source down.

`R` shows: `AF=0044 -Z-P-- 8031` (flags S Z H P/V N C, "-" when clear; then the PC after EXIT),
`BC DE`, `HL IX`, `IY SP`.

## API for programs
Call these with `CALL name`; the names are built in. Unless noted, they keep BC, DE, HL, IX, IY.

| Name | Address | |
|---|---|---|
| `PRINTSTR` | 8010 | print the text at HL, ending in 0; HL ends after the 0 (A, F) |
| `PUTCHAR` | 8013 | print A: characters, CR (13), LF (10), BS (8), 12 clears, 7 beeps; keeps everything |
| `GETKEY` | 8016 | wait for a key, A = its code (F) |
| `KEYPOLL` | 8019 | A = a key code or 0 (Z when none), without waiting (F) |
| `CLS` | 801C | clear the screen, cursor to the top left (A, F) |
| `SETCUR` | 801F | cursor to row D (0-3), column E (0-19) (A, F) |
| `PRHEX8` | 8022 | print A as two hex digits (A, F) |
| `PRHEX16` | 8025 | print HL as four hex digits (A, F) |
| `PRDEC` | 8028 | print HL in decimal (A, F) |
| `BEEP` | 802B | 0.1 s beep; keeps everything |
| `DELAY` | 802E | wait about HL milliseconds (A, F, HL) |
| `EXIT` | 8031 | back to EASM; R shows the registers (never returns) |
| `NEWLINE` | 8034 | new line unless at the start of one; keeps everything |

Key codes from GETKEY/KEYPOLL: ASCII and code page 850 characters, ENTER 13, ANSWER 27, DELETE 8,
DEL 127, LEFT 136, RIGHT 137, down 138, up 139, ALT+LEFT 140, ALT+RIGHT 141, HELP 142, TAB 9, and the
activity keys 192-213, 240-255 in panel order. The table stays at these addresses in later versions.

## The guide
HELP opens an index: topics first (start here, keys, commands, monitor, syntax, numbers, expressions,
directives, registers, flags, conditions, addressing, API, memory map, errors, an example), then one
page for every mnemonic and directive. Ü and ; (or LEFT/RIGHT) move; a letter jumps to the mnemonics
from that letter; ENTER opens a page, and on a page takes the example; ANSWER goes back.

Where the example goes:
* from the editor: a new line below the current one;
* from the command prompt: if it is a command (the pages "Commands" and "Monitor"), onto the command
  line, ready to run with ENTER; if it is code (every other page), into the editor as a new line;
* from `A`: onto its line, ready to assemble.

## Limits
* Text and symbols: 2816 bytes together (0xC500-0xCFFF). A line takes its length + 1 byte, and
  leading spaces take 1 byte. Each symbol takes its name + 3 bytes while the text is assembled.
* Code: 2816 bytes (0xD000-0xDAFF).
* No macros, no include files, no conditional assembly, no listing, no storage: the text lives in RAM
  and is lost when the Genio is switched off (see [STATUS.md](STATUS.md)).
