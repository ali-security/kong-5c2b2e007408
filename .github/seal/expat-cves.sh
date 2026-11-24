#!/bin/bash
# libexpat reproducers against the installed kong package (see expat/expat.lua).
# usage: expat-cves.sh <results-dir>
set -u
OUT=$(realpath -m "$1"); mkdir -p "$OUT"
D=$(cd "$(dirname "$0")/expat" && pwd)
L=/usr/local/openresty/luajit/bin/luajit
r8176=$(cd /tmp && "$L" "$D/expat.lua" 8176 2>/dev/null; echo "rc=$?")
r115506=$(cd /tmp && "$L" "$D/expat.lua" 115506 "$D/cve-2026-115506-a.xml" 2>&1)
r93990=$(cd /tmp && "$L" "$D/expat.lua" 93990 2>&1)
{
  echo "expat_8176 $(echo $r8176 | tr '\n' ' ')"
  echo "expat_115506 $r115506"
  echo "expat_93990 $r93990"
} | tee -a "$OUT/poc.txt" "$OUT/expat.txt"
