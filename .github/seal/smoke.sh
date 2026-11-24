#!/bin/bash
# Smoke test the installed Kong package: DB-less Kong proxying HTTP/1.1, HTTP/2 over TLS (8443),
# cleartext HTTP/2 (8000) and gRPC / gRPCs to Kong's own gRPC test target, then h2spec against 8443.
# Expects grpcurl, h2spec and /tmp/grpc-target on PATH / disk.
# usage: smoke.sh <results-dir>
set -euo pipefail
OUT=$(realpath -m "$1")
mkdir -p "$OUT"
SPEC=$(cd "$(dirname "$0")/../.." && pwd)/spec/fixtures/grpc

python3 -m http.server 9000 --bind 127.0.0.1 >/dev/null 2>&1 &
/tmp/grpc-target >/tmp/grpc-target.log 2>&1 &
sleep 2

cat > /tmp/kong.yml <<'EOF'
_format_version: "3.0"
services:
- name: http
  url: http://127.0.0.1:9000
  routes:
  - name: http
    paths: ["/"]
- name: grpc
  url: grpc://127.0.0.1:15010
  routes:
  - name: grpc
    protocols: ["grpc", "grpcs"]
    paths: ["/targetservice.Bouncer/"]
EOF

# run Kong from /tmp: its default lua_package_path starts with ./?.lua, and the checkout would shadow
# the installed package's Lua code
cd /tmp
export KONG_DATABASE=off KONG_DECLARATIVE_CONFIG=/tmp/kong.yml
export KONG_PROXY_LISTEN="0.0.0.0:8000 http2 reuseport backlog=16384, 0.0.0.0:8443 http2 ssl reuseport backlog=16384"
export KONG_ADMIN_LISTEN="127.0.0.1:8001 reuseport backlog=16384, 127.0.0.1:8444 http2 ssl reuseport backlog=16384"
kong version | tee "$OUT/kong-version.txt"
/usr/local/openresty/nginx/sbin/nginx -V 2>&1 | tee "$OUT/nginx-V.txt"
kong start
sleep 3
grep -n 'http2' /usr/local/kong/nginx-kong.conf | tee "$OUT/kong-http2-directives.txt" || true

check() { # name, expected, actual
  if [ "$2" == "$3" ]; then echo "PASS $1 ($3)" | tee -a "$OUT/smoke.txt"; else echo "FAIL $1 expected=$2 got=$3" | tee -a "$OUT/smoke.txt"; fi
}
check http1.1-8000 "200 1.1" "$(curl -s -o /dev/null -w '%{http_code} %{http_version}' http://127.0.0.1:8000/)"
check h2-tls-8443 "200 2" "$(curl -sk --http2 -o /dev/null -w '%{http_code} %{http_version}' https://127.0.0.1:8443/)"
check h2c-8000 "200 2" "$(curl -s --http2-prior-knowledge -o /dev/null -w '%{http_code} %{http_version}' http://127.0.0.1:8000/)"
GRPC="-import-path $SPEC -proto targetservice.proto -d {\"greeting\":\"seal\"}"
check grpc-8000 "hello seal" "$(grpcurl -plaintext $GRPC 127.0.0.1:8000 targetservice.Bouncer.SayHello | python3 -c 'import json,sys; print(json.load(sys.stdin)["reply"])')"
check grpcs-8443 "hello seal" "$(grpcurl -insecure $GRPC 127.0.0.1:8443 targetservice.Bouncer.SayHello | python3 -c 'import json,sys; print(json.load(sys.stdin)["reply"])')"

h2spec -t -k -h 127.0.0.1 -p 8443 -o 5 > "$OUT/h2spec.txt" 2>&1 || true
tail -3 "$OUT/h2spec.txt"
grep -E '^[0-9]+ tests, [0-9]+ passed' "$OUT/h2spec.txt" > "$OUT/h2spec-summary.txt" || true

kong stop
chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUT"
! grep -q '^FAIL' "$OUT/smoke.txt"
