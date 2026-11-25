#!/bin/bash
# Kong's PDK Test::Nginx suite (t/, as upstream's pdk-tests job runs it: prove -I. -r t) against the
# installed package's nginx. The Lua under test is this checkout's (the same PDK code in both legs);
# what differs between the sealed and upstream legs is the nginx/OpenResty/LuaJIT binary.
# A CI-only copy of t/Util.pm adds the package's Lua module paths, which upstream's job gets from
# its dev build's venv instead.
# usage: pdk-tests.sh <results-dir>
set -u
OUT=$(realpath -m "$1"); mkdir -p "$OUT"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
if ! perl -MTest::Nginx -e1 2>/dev/null; then
  curl -fsSL -o /tmp/cpanm https://cpanmin.us && chmod +x /tmp/cpanm
  /tmp/cpanm --notest --local-lib="$HOME/perl5" local::lib Test::Nginx > "$OUT/pdk-cpanm.log" 2>&1
fi
eval "$(perl -I "$HOME/perl5/lib/perl5" -Mlocal::lib 2>/dev/null)"
OVR=/tmp/seal-pdk-inc; mkdir -p "$OVR/t"
sed -e "s#^our \$LuaPackagePath = .*#our \$LuaPackagePath = \"lua_package_path '\$cwd/?.lua;\$cwd/?/init.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;;'; lua_package_cpath '/usr/local/lib/lua/5.1/?.so;;';\";#" \
  "$ROOT/t/Util.pm" > "$OVR/t/Util.pm"
grep -q "/usr/local/share/lua/5.1" "$OVR/t/Util.pm" || { echo "Util.pm override failed"; exit 1; }
cd "$ROOT"
export TEST_NGINX_BINARY=/usr/local/openresty/nginx/sbin/nginx
timeout 3000 prove -I"$OVR" -I. -r t > "$OUT/pdk-tests.log" 2>&1
tail -3 "$OUT/pdk-tests.log"
sed -n '/Test Summary Report/,$p' "$OUT/pdk-tests.log" | grep -oE '^t/\S+\.t' | sort > "$OUT/pdk-tests-failures.txt"
grep -E '^(Files=|Result:)' "$OUT/pdk-tests.log" | tr '\n' ' ' > "$OUT/pdk-tests-totals.txt"; echo >> "$OUT/pdk-tests-totals.txt"
echo "failing files:"; cat "$OUT/pdk-tests-failures.txt"
exit 0
