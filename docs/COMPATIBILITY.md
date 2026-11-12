# EASM compatibility report

## Where it was tested
**Only in MAME**, with the `genio2000` driver of `~/PROYECTOS/genio2000/mame-upstream` (the `genio`
build), headless, through `tests/run_tests.sh`. MAME was not modified for EASM. Nothing of EASM has
run on a real Genio 2000.

Results of the final image (`tests/results/`):

| Test | Result |
|---|---|
| `t00_smoke` start-up, calculator | 6 / 6 checks |
| `t01_demo` the demonstration program, typed, assembled, run, back to the editor | 15 / 15 |
| `t02_directives` labels, forward references, directives, expressions, SYM | 9 / 9 |
| `t03_errors` 15 error cases, line numbers, the editor at the error | 48 / 48 |
| `t04_editor` editing, long lines, line numbers, activity keys, guide (page 2), FIND, LINE | 28 / 28 |
| `t05_monitor` A D M E F C G R, user-RAM protection, API, EXIT, ANSWER break | 26 / 26 |
| `t06_keys` ASM/RUN keys, guide from the command line, NEW | 15 / 15 |
| `t07_limits` text full, symbol table full, BYE to the firmware | 6 / 6 |
| `insn.py` all official instruction forms: EASM's bytes and its disassembly vs MAME's `unidasm` | 697 forms, 0 differences |
| `opsweep.py` every opcode after every prefix through EASM's disassembler vs `unidasm` | 5326 instructions, 0 differences in documented opcodes |

The guide's switch to the second cartridge page and back is exercised by `t04` and `t06` (the guide
lives in page 2 and calls page 1 for every key and every character it draws).

### Differences from `unidasm` (undocumented or empty opcodes only)
* An empty `ED nn` slot: EASM shows `DB ED,$nn` and takes two bytes, as the Z80 executes it (a
  two-byte no-operation); `unidasm` shows `db $ed` and continues at the next byte.
* `DD CB d op` with a register in z: EASM shows the official `(IX+d)` form; `unidasm` also names the
  register that receives the result.
* `ED 4C, 54, ...` (NEG mirrors) and `ED 5D, 6D, 7D`: EASM shows `NEG` and `RETN` (the decoding table);
  `unidasm` marks the NEG mirrors with `*` and calls the others `RETI`.
* `SLL`, `IXH/IXL`, `IN F,(C)`, `OUT (C),0`: shown by both, in slightly different spellings.

## Risks on the real unit
EASM inherits EBASIC's drivers, which were verified only in MAME too. Most serious first:
1. **The second cartridge page (0x83)**: the selector bit was measured on the RevD board, but no code
   has run from the second half on the unit. Only the guide is there: if the page does not switch,
   everything but HELP still works, and HELP would crash.
2. **The firmware ISR as cursor service and timer**: it relies on firmware internals (DB00/DB01,
   DCF0-DCF7, hook DFF5) in one combination; EBASIC's `hwtest` measured the parts separately. Without
   the expected vector EASM runs with interrupts off: no cursor and no ANSWER break, the rest works.
3. **ANSWER break from the interrupt hook**: it drives and reads port 0x10 from inside the firmware's
   interrupt routine. Untested on the unit.
4. **LCD timing**: no busy-flag read; about 70 µs per write.
5. **The keyboard**: ghosting with several keys held; the ALT symbols.
6. **Uninitialised RAM** at power-up (MAME clears it): EASM initialises every variable it uses and the
   text at start-up; the screen save area is written before it is read.
7. **Timing of `DELAY`**: counted in T-states for 6.13 MHz; interrupts make it a little longer. MAME's
   interrupt is 50 Hz, the unit's 46.76 Hz.

## Compatibility with other Z80 assemblers
EASM reads Zilog syntax, close to most assemblers, with these differences:
* No macros, `INCLUDE`, `IF`, `ALIGN`, `PHASE`, local labels, listing or object files.
* `SUB`, `AND`, `OR`, `XOR`, `CP` take one operand (`SUB B`, not `SUB A,B`); `ADD`, `ADC`, `SBC` take `A,`.
* An operand that starts with `(` is an indirect address: write `LD A,2*(1+2)` rather than `LD A,(1+2)*2`.
* Expressions are 16 bits with C-like operators (`& | ^ ~ << >> %`); no `HIGH`/`LOW` (use `>>8` and
  `&0FFH`), no `.AND.`-style words, no relational operators.
* Hex: `0FFH`, `$FF`, `0xFF`, `&FF`; binary `%1010`, `1010B`. In the monitor, plain hex.
* `$` is the address of the statement (in `DB`/`DW` too).
* `DEFM` is a synonym of `DB`.
* Names are case-insensitive and significant to 15 characters; register names cannot be labels.
* A label in column 0 does not need `:` unless its name is a mnemonic or directive.
* Undocumented instructions (`SLL`, `IXH`, ...) are not assembled (the disassembler shows them).
