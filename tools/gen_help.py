#!/usr/bin/env python3
# Builds the data of the HELP guide (help.s) from help.txt. Adapted from EBASIC's gen_help.py.
#   * Checks that every mnemonic of ASMB.Z80's opcode table, and every directive, has an entry.
#   * Compresses the entry texts with a dictionary of up to 128 pieces (bytes 0x80-0xFF);
#     byte 1 escapes a code page 850 character, 10 is a new line.
#   * Lays every page out exactly as hwrap in help.s does and fails if one does not fit.
# Usage: gen_help.py help.txt ASMB.Z80 out/helpdata.s
# Copyright (C) 2026 Santiago Crespo
# SPDX-License-Identifier: GPL-3.0-or-later
import re
import sys
from collections import Counter

src, main, out = sys.argv[1:4]
LF = 10
MAXLEN = 250		# the page text in BUFFER (256 bytes)
MAXLINES = 20		# LINES in help.s


def cp850(s):
    return s.encode("cp850")


# ---- entries
entries = []
for line in open(src, encoding="utf-8"):
    line = line.rstrip("\n")
    if line.startswith("#"):
        continue
    if line.startswith("@"):
        entries.append({"title": line[1:], "body": [], "ex": ""})
    elif line.startswith("="):
        entries[-1]["ex"] = line[1:]
    elif entries:
        entries[-1]["body"].append(line)
for e in entries:
    paras, cur = [], []
    for l in e["body"]:
        if l.strip():
            cur.append(l.strip())
        elif cur:
            paras.append(" ".join(cur))
            cur = []
    if cur:
        paras.append(" ".join(cur))
    e["text"] = "\n".join(paras)

# ---- coverage: every mnemonic of ASMB.Z80's OPCODS table and every directive needs an entry
lines = open(main, encoding="latin-1").read().split("\n")
i = next(n for n, l in enumerate(lines) if l.startswith("OPCODS:"))
names, cur = set(), ""
while not lines[i].startswith("OPRNDS:"):
    l = lines[i].split(";")[0]
    m = re.search(r"DEFM\s+'([^']*)'", l)
    if m:
        cur += m.group(1)
    m = re.search(r"DEFB\s+'(''|.)'\+80H", l)
    if m:
        names.add((cur + m.group(1)[0]).split("\0")[0])
        cur = ""
    elif re.search(r"DEFB\s+0\s*$", l) and cur:
        cur += "\0"			# a separator inside a name ("EX", 0, "AF")
    i += 1
names = {n for n in names if re.fullmatch(r"[A-Z]+", n)} - {"DEFM", "DEFB", "DEFW", "OPT", "B", "M", "W"}	# (BASIC's DEF token + letter, and OPT)
DIRECTIVES = {"ORG", "EQU", "DB", "DEFB", "DEFM", "DW", "DEFW", "DS", "DEFS", "END"}
need = names | DIRECTIVES
have = {e["title"] for e in entries}
missing = sorted(need - have)
if missing:
    sys.exit("help.txt has no entry for: " + " ".join(missing))
extra = sorted(t for t in have - need if re.fullmatch(r"[A-Z]+", t))
if extra:
    sys.exit("help.txt has entries for unknown mnemonics: " + " ".join(extra))

# ---- order: the pages that are not keywords first (as in help.txt), then the keywords by title
head = [e for e in entries if not re.fullmatch(r"[A-Z]+", e["title"])]
rest = sorted((e for e in entries if e not in head), key=lambda e: e["title"])
entries = head + rest
assert len(entries) < 256


# ---- page layout (the same as hwrap)
def page(e):
    p = cp850(e["title"]) + bytes([LF]) + cp850(e["text"])
    if e["ex"]:
        p += bytes([LF]) + b"e.g. " + cp850(e["ex"])
    return p


def wrap(t):
    res, c = [], 0
    while c != len(t):
        start, d, k = c, None, 0
        while True:
            l = c + k
            if l == len(t):
                end, nxt = l, l
                break
            if t[l] == LF:
                end, nxt = l, l + 1
                break
            if t[l] == 0x20:
                d = l
            k += 1
            if k == 20:
                l = c + 20
                if l == len(t):
                    end, nxt = l, l
                elif t[l] == 0x20 or t[l] == LF:
                    end, nxt = l, l + 1
                elif d is None:
                    end, nxt = l, l
                else:
                    end, nxt = d, d + 1
                break
        res.append(t[start:end])
        c = nxt
    return res


for e in entries:
    p = page(e)
    if len(p) > MAXLEN:
        sys.exit("%s: page of %d characters (at most %d)" % (e["title"], len(p), MAXLEN))
    if len(wrap(p)) > MAXLINES:
        sys.exit("%s: %d lines (at most %d)" % (e["title"], len(wrap(p)), MAXLINES))

# ---- dictionary: greedy, by bytes saved
texts = [[cp850(e["text"])] for e in entries] + [[cp850(e["ex"])] for e in entries]	# pieces and int tokens
dic = []
while len(dic) < 128:
    cnt = Counter()
    for t in texts:
        for piece in t:
            if isinstance(piece, bytes):
                for m in re.finditer(rb"[A-Za-z$]+[ :(]?|[ (][A-Za-z]+|[A-Z]+ [0-9]+[:,]", piece):
                    if len(m.group(0)) >= 3:
                        cnt[m.group(0)] += 1
    best, gain = None, 0
    for w, n in cnt.items():
        g = n * (len(w) - 1) - (len(w) + 1)
        if g > gain:
            best, gain = w, g
    if best is None:
        break
    tok = len(dic)
    dic.append(best)
    for t in texts:
        new = []
        for piece in t:
            if isinstance(piece, bytes):
                parts = piece.split(best)
                for j, part in enumerate(parts):
                    if part:
                        new.append(part)
                    if j < len(parts) - 1:
                        new.append(tok)
            else:
                new.append(piece)
        t[:] = new


def encode(t):
    b = bytearray()
    for piece in t:
        if isinstance(piece, int):
            b.append(0x80 + piece)
        else:
            for c in piece:
                b += bytes([1, c]) if c >= 0x80 else bytes([c])
    return bytes(b)


def asm_bytes(b):
    return "\n".join("\t.db\t" + ",".join("0x%02X" % x for x in b[i:i + 16]) for i in range(0, len(b), 16))


codes = [encode(t) for t in texts]
body, exs = codes[:len(entries)], codes[len(entries):]
for name, orig, b in zip([e["title"] for e in entries] * 2,
                         [cp850(e["text"]) for e in entries] + [cp850(e["ex"]) for e in entries], codes):
    assert 0 not in b
    # decoding gives the text back
    dec, j = bytearray(), 0
    while j < len(b):
        if b[j] >= 0x80:
            dec += dic[b[j] - 0x80]
        elif b[j] == 1:
            j += 1
            dec.append(b[j])
        else:
            dec.append(b[j])
        j += 1
    assert bytes(dec) == orig, name

o = ["; Generated by gen_help.py from %s. Do not edit." % src, "\t.area\tP2",
     "HCOUNT::\t.db\t%d" % len(entries), "HKW::\t.db\t%d\t; first keyword entry" % len(head), "HIDX::"]
o += ["\t.dw\the%d" % n for n in range(len(entries))]
o.append("HDICT::")
for w in dic:
    o.append("\t.db\t%d\n\t.ascii\t\"%s\"" % (len(w), w.decode()))
for n, (e, b) in enumerate(zip(entries, body)):
    o.append("he%d:\t; %s" % (n, e["title"]))
    o.append(asm_bytes(cp850(e["title"]) + b"\0" + b + b"\0" + exs[n] + b"\0"))
open(out, "w").write("\n".join(o) + "\n")
raw = sum(len(cp850(e["text"]) + cp850(e["ex"])) for e in entries)
size = sum(len(b) for b in codes)
print("help: %d entries, %d mnemonics and directives covered; texts and examples %d -> %d bytes, dictionary %d pieces (%d bytes)" %
      (len(entries), len(need), raw, size, len(dic), sum(len(w) + 1 for w in dic)))
