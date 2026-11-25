#!/bin/bash
# PCRE2 reproducers through the PCRE2 10.44 statically linked into the package's nginx, driven by
# ngx.re under resty (DFA mode for CVE-2026-86145, JIT with ngx.re.opt jit_stack_size for
# CVE-2026-103111). Each script prints "ok" when the fixed behaviour is seen; a crash shows as rc.
# usage: pcre2-cves.sh <results-dir>
set -u
OUT=$(realpath -m "$1"); mkdir -p "$OUT"
D=$(cd "$(dirname "$0")/pcre2" && pwd)
cd /tmp
for c in 86145 103111; do
  timeout 60 /usr/local/openresty/bin/resty "$D/cve-2026-$c.lua" > "$OUT/pcre2-$c.out" 2>&1; rc=$?
  echo "pcre2_$c result=$(tail -1 "$OUT/pcre2-$c.out" | cut -c1-40)/rc=$rc"
done | tee "$OUT/pcre2.txt" >> "$OUT/poc.txt"
cat "$OUT/pcre2.txt"
