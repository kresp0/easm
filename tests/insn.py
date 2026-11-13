#!/usr/bin/env python3
# The instruction-set test: every official Z80 instruction form, assembled by EASM in MAME and checked
# against MAME's own disassembler (unidasm, an independent decoder), then disassembled by EASM's D
# command and compared again.
#   insn.py gen DIR     write DIR/insn_N.asm (sources) and DIR/t_insn_N.txt (MAME scripts)
#   insn.py check DIR   read the logs DIR/insn_N/drive.log and check them; exit status 1 on a mismatch
# Copyright (C) 2026 Santiago Crespo
# SPDX-License-Identifier: 0BSD
import os
import re
import subprocess
import sys

R = ["B", "C", "D", "E", "H", "L", "(HL)", "A"]
R7 = ["B", "C", "D", "E", "H", "L", "A"]
CC = ["NZ", "Z", "NC", "C", "PO", "PE", "P", "M"]
N, NN = "12H", "1234H"


def idx(x, d):
    return "(%s%+d)" % (x, d)


def forms():
    f = []
    # 8-bit loads
    for a in R:
        for b in R:
            if not (a == b == "(HL)"):
                f.append("LD %s,%s" % (a, b))
        f.append("LD %s,%s" % (a, N))
    for x, d in (("IX", 5), ("IY", -3)):
        for r in R7:
            f.append("LD %s,%s" % (r, idx(x, d)))
            f.append("LD %s,%s" % (idx(x, d), r))
        f.append("LD %s,%s" % (idx(x, d), N))
    f += ["LD A,(BC)", "LD A,(DE)", "LD A,(%s)" % NN, "LD (BC),A", "LD (DE),A", "LD (%s),A" % NN,
          "LD A,I", "LD A,R", "LD I,A", "LD R,A"]
    # 16-bit loads
    for rp in ["BC", "DE", "HL", "SP", "IX", "IY"]:
        f += ["LD %s,%s" % (rp, NN), "LD %s,(%s)" % (rp, NN), "LD (%s),%s" % (NN, rp)]
    f += ["LD SP,HL", "LD SP,IX", "LD SP,IY"]
    for q in ["BC", "DE", "HL", "AF", "IX", "IY"]:
        f += ["PUSH " + q, "POP " + q]
    # exchanges and blocks
    f += ["EX DE,HL", "EX AF,AF'", "EXX", "EX (SP),HL", "EX (SP),IX", "EX (SP),IY",
          "LDI", "LDIR", "LDD", "LDDR", "CPI", "CPIR", "CPD", "CPDR"]
    # 8-bit arithmetic
    for op in ["ADD A,", "ADC A,", "SUB ", "SBC A,", "AND ", "XOR ", "OR ", "CP "]:
        for s in R + [N, idx("IX", 7), idx("IY", -128)]:
            f.append(op + s)
    for op in ["INC ", "DEC "]:
        for s in R + [idx("IX", 1), idx("IY", 127)]:
            f.append(op + s)
    f += ["DAA", "CPL", "NEG", "CCF", "SCF", "NOP", "HALT", "DI", "EI", "IM 0", "IM 1", "IM 2"]
    # 16-bit arithmetic
    for ss in ["BC", "DE", "HL", "SP"]:
        f += ["ADD HL," + ss, "ADC HL," + ss, "SBC HL," + ss, "INC " + ss, "DEC " + ss]
    for x in ["IX", "IY"]:
        for pp in ["BC", "DE", x, "SP"]:
            f.append("ADD %s,%s" % (x, pp))
        f += ["INC " + x, "DEC " + x]
    # rotations, shifts, bits
    f += ["RLCA", "RLA", "RRCA", "RRA", "RLD", "RRD"]
    for op in ["RLC", "RL", "RRC", "RR", "SLA", "SRA", "SRL"]:
        for s in R + [idx("IX", 2), idx("IY", -2)]:
            f.append("%s %s" % (op, s))
    for op in ["BIT", "SET", "RES"]:
        for b in range(8):
            for s in R + [idx("IX", 3), idx("IY", -4)]:
                f.append("%s %d,%s" % (op, b, s))
    # jumps, calls, returns
    f += ["JP " + NN, "JR $+5", "JR $-3", "JP (HL)", "JP (IX)", "JP (IY)", "DJNZ $+2", "CALL " + NN,
          "RET", "RETI", "RETN"]
    for c in CC:
        f += ["JP %s,%s" % (c, NN), "CALL %s,%s" % (c, NN), "RET " + c]
    for c in CC[:4]:
        f.append("JR %s,$+10" % c)
    for p in range(0, 0x40, 8):
        f.append("RST %02XH" % p)
    # input and output
    f += ["IN A,(%s)" % N, "OUT (%s),A" % N, "INI", "INIR", "IND", "INDR", "OUTI", "OTIR", "OUTD", "OTDR"]
    for r in R7:
        f += ["IN %s,(C)" % r, "OUT (C),%s" % r]
    return f


CHUNK = 160


def gen(d):
    os.makedirs(d, exist_ok=True)
    f = forms()
    chunks = [f[i:i + CHUNK] for i in range(0, len(f), CHUNK)]
    for n, c in enumerate(chunks):
        open("%s/insn_%d.asm" % (d, n), "w").write("".join("  %s\n" % l for l in c))
        s = ["wait 1.5", "load gen/insn_%d.asm" % n, "type ASM\\n", "wait 3", "dump asm",
             "peek D000 1200", "type D D000\\n", "wait 0.5", "dump d0"]
        for k in range(len(c) // 4 + 1):
            s += ["press AVANCE", "wait 0.25", "dump d%d" % (k + 1)]
        s.append("quit")
        open("%s/t_insn_%d.txt" % (d, n), "w").write("\n".join(s) + "\n")
    print(len(f), "instruction forms in", len(chunks), "chunks")
    return len(chunks)


def num(m):
    return str(int(m.group(1), 16))


def norm(t):
    """Lower case, numbers in decimal, no spaces after commas, one space after the mnemonic."""
    t = t.strip().lower()
    t = re.sub(r"\$([0-9a-f]+)", num, t)
    t = re.sub(r"\b([0-9][0-9a-f]*)h\b", num, t)
    t = re.sub(r"\s+", " ", t)
    t = re.sub(r"\s*,\s*", ",", t)
    t = re.sub(r"\(\s*(i[xy])\s*([+-])\s*", r"(\1\2", t)
    t = t.replace("(ix+0)", "(ix)").replace("(iy+0)", "(iy)")
    t = re.sub(r"^(rld|rrd) \(hl\)$", r"\1", t)		# unidasm writes "rld (hl)"
    return t


def reloc(src, addr):
    """JR $+k etc.: the absolute target, as the disassemblers show it."""
    return re.sub(r"\$([+-]\d+)", lambda m: str(addr + int(m.group(1))), src)


def unidasm(code, base):
    open("/tmp/easm_insn.bin", "wb").write(code)
    out = subprocess.run(["unidasm", "/tmp/easm_insn.bin", "-arch", "z80", "-basepc", "%x" % base],
                         capture_output=True, text=True).stdout
    res = []
    for l in out.splitlines():
        m = re.match(r"([0-9a-f]+): ((?:[0-9a-f]{2} )+)\s*(.*)$", l)
        if m:
            res.append((int(m.group(1), 16), len(m.group(2).split()), m.group(3)))
    return res


def check(d):
    bad, total = 0, 0
    n = 0
    while os.path.exists("%s/insn_%d.asm" % (d, n)):
        src = [l.strip() for l in open("%s/insn_%d.asm" % (d, n))]
        log = open("%s/insn_%d/drive.log" % (d, n)).read()
        m = re.search(r"peek D000 [^:]*: ((?:[0-9A-F]{2} )+)", log)
        code = bytes(int(x, 16) for x in m.group(1).split())
        dis = unidasm(code, 0xD000)
        # EASM's own disassembly: the rows of the D screens after "D D000", one instruction per row
        easm = []
        for scr in re.findall(r"--- d\d+ t=[\d.]+\n((?:\|.*\|\n){4})", log):
            for row in scr.splitlines():
                m2 = re.match(r"\|([0-9A-F]{4}) (.*?)\s*\|$", row)
                if m2:
                    easm.append((int(m2.group(1), 16), m2.group(2)))
        easm_at = {}
        for a, t in easm:
            easm_at.setdefault(a, t)
        if "Error" in log or "Line " in log.split("--- asm")[1][:200]:
            print("chunk %d: EASM reported an error:" % n)
            print(log.split("--- asm")[1][:200])
            bad += 1
        for i, s in enumerate(src):
            total += 1
            if i >= len(dis):
                print("chunk %d line %d: %s: no code" % (n, i + 1, s))
                bad += 1
                continue
            addr, size, text = dis[i]
            want = norm(reloc(s, addr))
            if norm(text) != want:
                print("chunk %d line %d @%04X: %-16s unidasm: %s" % (n, i + 1, addr, s, text))
                bad += 1
            e = easm_at.get(addr)
            if e is None:
                print("chunk %d line %d @%04X: %-16s EASM's D did not show it" % (n, i + 1, addr, s))
                bad += 1
            elif norm(e) != norm(text):
                print("chunk %d line %d @%04X: %-16s EASM D: %-16s unidasm: %s" % (n, i + 1, addr, s, e, text))
                bad += 1
        n += 1
    print("%d instruction forms checked, %d problems" % (total, bad))
    return bad


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2])
    else:
        sys.exit(1 if check(sys.argv[2]) else 0)
