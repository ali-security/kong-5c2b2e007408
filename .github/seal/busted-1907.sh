#!/bin/bash
# Kong's own busted specs for the CVE-2026-1907 backport, run with the installed package's resty/nginx
# and this checkout's Lua (the package's Lua plus the backport). busted 2.2.0 (Kong's DEV_ROCKS pin)
# is installed from a local mirror of pinned rocks: luarocks.org's manifest no longer loads in LuaJIT.
# The integration spec runs its /v1/outlet tests only: its /v2/outlet tests need the RPC handler,
# which 3.8.0 never activates (cluster_rpc is forced off; /v2/outlet answers 500 even to valid peers).
# usage: busted-1907.sh <results-dir>   (as root; Postgres on 127.0.0.1:5432, user/password kong)
set -u
OUT=$(realpath -m "$1"); mkdir -p "$OUT"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
M=/tmp/seal-busted-mirror; mkdir -p "$M"
while read -r name version ext; do
  curl -fsSL -o "$M/$name-$version.$ext" "https://luarocks.org/$name-$version.$ext"
done < "$ROOT/.github/seal/busted-rocks.txt"
/usr/bin/luarocks-admin make_manifest "$M" >/dev/null
/usr/local/bin/luarocks install --only-server="$M" busted 2.2.0 > "$OUT/busted-install.log" 2>&1 || { echo "busted install failed"; tail "$OUT/busted-install.log"; }
PGPASSWORD=kong psql -h 127.0.0.1 -U kong -d kong -qc 'create database kong_tests' 2>/dev/null || true
export KONG_TEST_PG_HOST=127.0.0.1 KONG_TEST_PG_USER=kong KONG_TEST_PG_PASSWORD=kong KONG_TEST_PG_DATABASE=kong_tests
cd "$ROOT"
run() {
  local name=$1; shift
  timeout 1200 resty bin/busted -o gtest "$@" > "$OUT/busted-$name.log" 2>&1; local rc=$?
  local passed failed
  passed=$(grep -oE '^\[  PASSED  \] [0-9]+' "$OUT/busted-$name.log" | grep -oE '[0-9]+$')
  failed=$(grep -oE '^\[  FAILED  \] [0-9]+ tests' "$OUT/busted-$name.log" | grep -oE '[0-9]+')
  echo "busted_1907_$name rc=$rc passed=${passed:-0} failed=${failed:-0}"
}
{
  run hostname spec/01-unit/33-tools_hostname_spec.lua
  run utils spec/01-unit/05-utils_spec.lua
  run sql_injection_v1 --filter='v1/outlet' spec/02-integration/18-hybrid_rpc/11-sql_injection_spec.lua
} | tee "$OUT/busted-1907.txt" >> "$OUT/poc.txt"
cat "$OUT/busted-1907.txt"
chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUT" "$ROOT" 2>/dev/null || true
