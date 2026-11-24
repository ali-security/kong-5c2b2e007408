#!/bin/bash
# OpenSSL reproducers against the libcrypto/libssl in the installed kong package.
# Builds the stock openssl-3.2.1 command-line tool and runs it with LD_LIBRARY_PATH pointing at
# /usr/local/kong/lib, so every call goes into the package's libraries. The inputs are the upstream
# regression-test files that build/openresty/openssl/patches adds (PEM-wrapped where upstream ships DER).
# usage: openssl-cves.sh <results-dir>
set -u
OUT=$(realpath -m "$1"); mkdir -p "$OUT"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
W=/tmp/seal-openssl; mkdir -p "$W/pristine" "$W/data"; cd "$W"
curl -fsSL -o openssl.tgz https://github.com/openssl/openssl/releases/download/openssl-3.2.1/openssl-3.2.1.tar.gz
echo "83c7329fe52c850677d75e5d0b0ca245309b97e8ecbcfdc1dfdc4ab9fac35b39  openssl.tgz" | sha256sum -c --quiet
tar xzf openssl.tgz -C pristine --strip-components=1
tar xzf openssl.tgz -C data --strip-components=1
(cd data && for p in "$ROOT"/build/openresty/openssl/patches/*.patch; do patch -p1 -s -F0 < "$p"; done)
(cd pristine && ./config shared no-threads -DPURIFY >/dev/null && make -j"$(nproc)" build_programs >/dev/null)

export LD_LIBRARY_PATH=/usr/local/kong/lib
O=$W/pristine/apps/openssl; S=$W/data; D=$S/test/recipes
ldd "$O" | grep -E 'lib(crypto|ssl)' | tee "$OUT/openssl-ldd.txt"

run() { local name=$1; shift; timeout 20 "$O" "$@" >/dev/null 2>&1 </dev/null; echo "openssl_$name rc=$?"; }
{
  run 2025_15467 cms -decrypt -inform PEM -in "$D/80-test_cmsapi_data/encDataWithTooLongIV.pem" -recip "$S/test/certs/servercert.pem" -inkey "$S/test/certs/serverkey.pem"
  run 2026_28388 verify -attime 1739527200 -CAfile "$S/test/certs/cve-2026-28388-ca.pem" -crl_check -use_deltas -CRLfile "$S/test/certs/cve-2026-28388-crls.pem" "$S/test/certs/cve-2026-28388-leaf.pem"
  run 2026_28389_dh cms -decrypt -inform PEM -in "$D/80-test_cms_data/dh-malformed.pem" -recip "$D/80-test_cms_data/dh-cert.pem" -inkey "$D/80-test_cms_data/dh-key.pem"
  run 2026_28389_ecdh cms -decrypt -inform PEM -in "$D/80-test_cms_data/ecdh-malformed.pem" -recip "$D/80-test_cms_data/ecdh-cert.pem" -inkey "$D/80-test_cms_data/ecdh-key.pem"
  run 2026_28390 cms -decrypt -inform PEM -in "$D/80-test_cms_data/rsa-malformed.pem" -recip "$S/test/smime-certs/smrsa3.pem" -inkey "$S/test/smime-certs/smrsa3-key.pem"
  run 2026_45447 smime -verify -noverify -in "$S/test/smime-eml/pkcs7-empty-digest-set.eml"
} | tee -a "$OUT/poc.txt" "$OUT/openssl.txt"
