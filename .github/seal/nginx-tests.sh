#!/bin/bash
# Run nginx/nginx-tests (pinned) for the areas the sealed nginx patches touch against the installed
# Kong nginx binary, and record the failing test files.
# usage: nginx-tests.sh <results-dir>
set -u
OUT=$1
NGINX_TESTS_REF=25320bfddec3fd53383ed6623aa7d1d2e791bebf
mkdir -p "$OUT"
if [ ! -d /tmp/nginx-tests ]; then
  git clone -q https://github.com/nginx/nginx-tests.git /tmp/nginx-tests
fi
cd /tmp/nginx-tests
git checkout -q "$NGINX_TESTS_REF"
git log -1 --format='nginx-tests %H' | tee "$OUT/nginx-tests-ref.txt"

export TEST_NGINX_BINARY=/usr/local/openresty/nginx/sbin/nginx
T=$(ls h2*.t rewrite*.t map*.t ssi*.t scgi*.t uwsgi*.t grpc*.t ssl*.t proxy*.t access_log*.t stream_access_log*.t \
      stream_ssl*.t http_resolver*.t stream_resolver*.t body*.t fastcgi*.t index*.t http_try_files*.t \
      http_location*.t http_variables*.t stream_variables*.t subrequest*.t 2>/dev/null | sort -u)
echo "$T" | wc -l | sed 's/^/test files: /'
prove -j"$(nproc)" $T > "$OUT/nginx-tests.log" 2>&1
tail -3 "$OUT/nginx-tests.log"
sed -n '/Test Summary Report/,$p' "$OUT/nginx-tests.log" | grep -oE '^\S+\.t' | sort > "$OUT/nginx-tests-failures.txt"
grep -E '^Files=' "$OUT/nginx-tests.log" > "$OUT/nginx-tests-totals.txt"
echo "failing files:"; cat "$OUT/nginx-tests-failures.txt"
exit 0
