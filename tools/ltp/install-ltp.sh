#!/usr/bin/env bash
# Install a pinned LTP release into a target prefix (default /opt/ltp).
#
# Pinned release: 20250930. Constraint: the release must still ship the
# `runltp` runner (it prints a deprecation notice pointing at kirk but
# works). Upstream removed runltp in 20260529 in favor of kirk; both
# cvtest and curvine's Portal ltp_test.py drive runltp, so the pin is
# load-bearing — do not bump to >= 20260529 without adapting to kirk's
# output format.
#
# Prereqs: gcc, make, bison, flex, sudo (for install).
#
# Usage: tools/ltp/install-ltp.sh [prefix]     (default /opt/ltp)
set -euo pipefail

LTP_VERSION="${LTP_VERSION:-20250930}"
PREFIX="${1:-/opt/ltp}"
TARBALL="ltp-full-${LTP_VERSION}.tar.bz2"
URL="https://github.com/linux-test-project/ltp/releases/download/${LTP_VERSION}/${TARBALL}"
WORKDIR="$(mktemp -d /tmp/cvtest-ltp-${LTP_VERSION}.XXXXXX)"

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo ">> Downloading LTP ${LTP_VERSION} ..."
curl -sSL -o "${WORKDIR}/${TARBALL}" "$URL"

echo ">> Building ..."
tar -xjf "${WORKDIR}/${TARBALL}" -C "$WORKDIR"
cd "${WORKDIR}/ltp-full-${LTP_VERSION}"

# listmount04 (added 2025) does not compile against kernel uapi >= 6.17
# ('struct mnt_id_req' has no member named 'spare'). Its install failure
# aborts the whole install descent, so drop it up front on affected
# kernels. Test is irrelevant to FUSE-backed POSIX validation.
if echo "#include <linux/mount.h>
int main(void){struct mnt_id_req r;return r.spare;}" \
    | gcc -x c - -o /dev/null 2>/dev/null; then
    : # old kernel headers, keep listmount04
else
    echo ">> kernel uapi incompatible with listmount04; dropping it from the build"
    rm -f testcases/kernel/syscalls/listmount/listmount04.c
fi

./configure --prefix="$PREFIX" > /dev/null
make -j"$(nproc)" -k
sudo make install -k

# Sanity: the two artifacts cvtest needs.
test -x "${PREFIX}/runltp" || { echo "ERROR: ${PREFIX}/runltp missing" >&2; exit 1; }
test -d "${PREFIX}/runtest" || { echo "ERROR: ${PREFIX}/runtest missing" >&2; exit 1; }
echo ">> LTP ${LTP_VERSION} installed at ${PREFIX} (runltp OK)"
