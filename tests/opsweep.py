#!/usr/bin/env python3
# Disassembler sweep: every opcode after every prefix (none, CB, ED, DD, FD, DD CB d, FD CB d), each
# followed by two 00 operand bytes, disassembled by EASM's D command in MAME and by MAME's unidasm.
#   opsweep.py gen DIR | opsweep.py check DIR
# Differences are listed; those in undocumented or empty opcodes are reported apart.
# Copyright (C) 2026 Santiago Crespo
# SPDX-License-Identifier: 0BSD
import os
import re
import sys
sys.path.insert(0, os.path.dirname(__file__))
from insn import norm, unidasm

PREFIXES = [[], [0xCB], [0xED], [0xDD], [0xFD], [0xDD, 0xCB, 0x05], [0xFD, 0xCB, 0xFB]]
SIZE = 2048


def stream():
    b = bytearray()
    for p in PREFIXES:
        for x in range(256):
            b += bytes(p) + bytes([x, 0, 0])
    return bytes(b)


def gen(d):
    os.makedirs(d, exist_ok=True)
    data = stream()
    n = 0
    for i in range(0, len(data), SIZE):
        part = data[i:i + SIZE]
        open("%s/ops_%d.bin" % (d, n), "wb").write(part)
        s = ["wait 1.5", "loadbin gen/ops_%d.bin D000" % n, "type D D000\\n", "wait 0.5", "dump d0"]
        for k in range(SIZE // 4):
            s += ["press AVANCE", "wait 0.2", "dump d%d" % (k + 1)]
        s.append("quit")
        open("%s/t_ops_%d.txt" % (d, n), "w").write("\n".join(s) + "\n")
        n += 1
    print(n, "parts")


def check(d):
    n, bad, undoc, total = 0, 0, 0, 0
    while os.path.exists("%s/ops_%d.bin" % (d, n)):
        code = open("%s/ops_%d.bin" % (d, n), "rb").read()
        log = open("%s/ops_%d/drive.log" % (d, n)).read()
        easm = {}
        for row in re.findall(r"^\|([0-9A-F]{4}) (.*?)\s*\|$", log, re.M):
            easm.setdefault(int(row[0], 16), row[1])
        prev = ""
        for addr, size, text in unidasm(code, 0xD000):
            if addr + size > 0xD000 + len(code) - 4:
                break
            e = easm.get(addr)
            # an empty ED slot: the CPU (and EASM) take ED nn as a two-byte NOP, unidasm one byte
            skip = e is None and norm(prev) == "db 237"
            prev = text
            if skip:
                continue
            total += 1
            if e is not None and norm(e) == norm(text):
                continue
            raw = code[addr - 0xD000:addr - 0xD000 + size].hex(" ")
            line = "%04X %-12s EASM: %-18s unidasm: %s" % (addr, raw, e, text)
            # undocumented: SLL, IXH/IXL/IYH/IYL, IN F/OUT 0, DD CB register forms, empty ED slots,
            # a prefix that changes nothing
            if re.search(r"sll|sl1|ix[hl]|iy[hl]|in 0|out \(c\),0|^db|^defb|^nop$|\?|^\w+ [a-l]=|,[a-l]$", norm(text)) \
                    or (e and re.match(r"(DB|IN F|OUT \(C\),0|SLL)", e)) \
                    or norm(text) == "neg *" or raw in ("ed 5d", "ed 6d", "ed 7d"):	# ED mirrors
                undoc += 1
                print("undocumented/empty:", line)
            else:
                bad += 1
                print("MISMATCH:", line)
        n += 1
    print("%d instructions compared, %d mismatches, %d differences in undocumented or empty opcodes" % (total, bad, undoc))
    return bad


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2])
    else:
        sys.exit(1 if check(sys.argv[2]) else 0)
