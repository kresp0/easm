#!/bin/sh
# Runs tests/shots.txt in headless MAME and joins its native LCD snapshots, x4, two per row, into screens_mame.png
# (the layout of the examples in kresp0/vtech-genio2000). MAME = checkout with mame/genio and roms_local/.
# Copyright (C) 2026 Santiago Crespo
# SPDX-License-Identifier: 0BSD
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=$HERE/out/shots
rm -rf "$OUT"
"$HERE/tests/run_mame.sh" "$HERE/tests/shots.txt" "$OUT" 60 -snapview native > /dev/null 2>&1 || true
python3 - "$OUT" "$HERE/screens_mame.png" <<'PY'
import glob, sys
from PIL import Image
fs = sorted(glob.glob(sys.argv[1] + "/genio2000/*.png"))
sheet = Image.new("RGB", (2 * 490, (len(fs) + 1) // 2 * 170), "white")
for i, f in enumerate(fs):
    sheet.paste(Image.open(f).convert("RGB").resize((480, 160), Image.NEAREST), ((i % 2) * 490, (i // 2) * 170))
sheet.save(sys.argv[2])
print("%d snapshots -> %s" % (len(fs), sys.argv[2]))
PY
