#!/bin/bash
# LuaJIT reproducers against the installed kong package: each script runs in the package's luajit
# binary and in nginx's embedded LuaJIT (resty), and prints "ok" when the fix is present.
# A crash shows as the exit status.
# usage: luajit-cves.sh <results-dir>
set -u
OUT=$(realpath -m "$1"); mkdir -p "$OUT"
D=$(cd "$(dirname "$0")/luajit" && pwd)
cd /tmp
for c in 25176 25177 25178; do
  f=$D/cve-2024-$c.lua
  timeout 60 /usr/local/openresty/luajit/bin/luajit "$f" > "$OUT/luajit-$c.out" 2>&1; brc=$?
  timeout 60 /usr/local/openresty/bin/resty "$f" > "$OUT/resty-$c.out" 2>&1; rrc=$?
  b=$(tail -1 "$OUT/luajit-$c.out"); r=$(tail -1 "$OUT/resty-$c.out")
  echo "luajit_$c luajit=${b:-none}/rc=$brc resty=${r:-none}/rc=$rrc"
done | tee "$OUT/luajit.txt" >> "$OUT/poc.txt"
cat "$OUT/luajit.txt"
