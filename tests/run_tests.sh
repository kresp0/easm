#!/bin/sh
# All the MAME tests: the scripted ones (tests/t*.txt), the instruction-set test against unidasm
# (tests/insn.py) and the disassembler sweep (tests/opsweep.py). Logs in tests/results/.
# Usage: tests/run_tests.sh [quick]   (quick: only the scripted tests)
# Copyright (C) 2026 Santiago Crespo
# SPDX-License-Identifier: GPL-3.0-or-later
cd "$(dirname "$0")/.." || exit 1
R=tests/results
mkdir -p $R
fail=0
for t in tests/t[0-9]*.txt; do
  n=$(basename "$t" .txt)
  tests/run_mame.sh "$t" "$R/$n" 300 >/dev/null 2>&1
  res=$(grep "^RESULT" "$R/$n/drive.log" || echo "RESULT none (MAME did not finish)")
  echo "$n: $res"
  case "$res" in *"fail=0"*) ;; *) fail=1 ;; esac
done
[ "$1" = quick ] && exit $fail
python3 tests/insn.py gen tests/gen >/dev/null
for s in tests/gen/t_insn_*.txt; do
  n=$(basename "$s" .txt | sed 's/^t_//')
  tests/run_mame.sh "$s" "tests/gen/$n" 300 >/dev/null 2>&1 &
done
wait
python3 tests/insn.py check tests/gen > $R/insn.txt || fail=1
echo "instruction set: $(tail -1 $R/insn.txt)"
python3 tests/opsweep.py gen tests/gen >/dev/null
for s in tests/gen/t_ops_*.txt; do
  n=$(basename "$s" .txt | sed 's/^t_//')
  tests/run_mame.sh "$s" "tests/gen/$n" 600 >/dev/null 2>&1 &
done
wait
python3 tests/opsweep.py check tests/gen > $R/opsweep.txt || fail=1
echo "disassembler sweep: $(tail -1 $R/opsweep.txt)"
[ $fail = 0 ] && echo "ALL PASSED" || echo "SOME TESTS FAILED"
exit $fail
