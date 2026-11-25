#!/bin/bash
# Wasm smoke test for the installed kong package: start Kong with wasm on (ngx_wasm_module compiles the
# bundled datakit filter with Wasmtime/Cranelift at startup), and record which cap-primitives source the
# shipped ngx_wasmx_module.so was built from (the sealed build vendors a patched copy).
# usage: wasm-smoke.sh <results-dir>   (as root)
set -u
OUT=$(realpath -m "$1"); mkdir -p "$OUT"
M=/usr/local/openresty/nginx/modules/ngx_wasmx_module.so
vendored=$(strings -a "$M" | grep -c 'vendor/cap-primitives/src' || true)
registry=$(strings -a "$M" | grep -c 'cap-primitives-3.0.0/src' || true)

cd /tmp
export KONG_PREFIX=/tmp/kong-wasm KONG_DATABASE=off KONG_WASM=on KONG_WASM_FILTERS=bundled
export KONG_PROXY_LISTEN="0.0.0.0:8100" KONG_ADMIN_LISTEN="127.0.0.1:8101"
started=0
kong start >/dev/null 2>&1 && started=1
sleep 2
filters=$(curl -s http://127.0.0.1:8101/filters/enabled 2>/dev/null | tr -d '\n' | cut -c1-200)
errors=$(grep -cE '\[(emerg|alert|crit)\]' "$KONG_PREFIX/logs/error.log" 2>/dev/null || true)
kong stop >/dev/null 2>&1

echo "wasm started=$started emerg_alert_crit=${errors:-0} cap_primitives_vendored=$vendored cap_primitives_registry=$registry filters=$filters" | tee "$OUT/wasm.txt"
echo "wasm_smoke started=$started errors=${errors:-0} vendored=$((vendored > 0)) registry=$((registry > 0))" >> "$OUT/poc.txt"
chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUT"
