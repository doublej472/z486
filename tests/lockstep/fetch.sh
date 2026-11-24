#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Fetch the lockstep reference model and build it: Tetrium at a pinned commit, the
# 86Box sources Tetrium's tb/x86ref patches (also pinned), then libx86ref.a.
# Nothing fetched here is committed: it all lands in the cache directory.
#
# usage: tests/lockstep/fetch.sh
#   LOCKSTEP_CACHE        cache directory (default tests/lockstep/build)
#   LOCKSTEP_TETRIUM_URL  clone source for Tetrium (default the public repository;
#                         a local checkout that holds the pinned commit works offline)
#   LOCKSTEP_86BOX_URL    clone source for 86Box (default the public repository)
#   JOBS                  compile jobs for libx86ref (default 4)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="${LOCKSTEP_CACHE:-$HERE/build}"
TETRIUM_URL="${LOCKSTEP_TETRIUM_URL:-https://github.com/ZbuntowanyKamulec/Tetrium.git}"
BOX_URL="${LOCKSTEP_86BOX_URL:-https://github.com/86Box/86Box.git}"
# Tetrium d5caa5a (README: block diagram of the CPU); 86Box as Tetrium's tests/fetch.sh pins it.
TETRIUM_SHA=d5caa5ae5a644864b4df22d378d3bf49e4ef3b55
BOX_SHA=7b2dbc034dd60b931faa0d42ec318dcccc8c86ac
JOBS="${JOBS:-4}"

T="$CACHE/tetrium"
LIB="$T/build/x86ref/libx86ref.a"
STAMP="$CACHE/x86ref.stamp"
WANT="tetrium $TETRIUM_SHA 86box $BOX_SHA"

if [[ -f "$LIB" && -f "$STAMP" && "$(cat "$STAMP")" == "$WANT" ]]; then
    echo "lockstep: libx86ref present ($LIB)"
    exit 0
fi

mkdir -p "$CACHE"
if [[ ! -d "$T/.git" ]]; then
    rm -rf "$T"
    echo "lockstep: cloning Tetrium from $TETRIUM_URL"
    git clone -q --no-checkout "$TETRIUM_URL" "$T"
fi
git -C "$T" cat-file -e "$TETRIUM_SHA^{commit}" 2>/dev/null || git -C "$T" fetch -q origin
git -C "$T" -c advice.detachedHead=false checkout -q --force "$TETRIUM_SHA"
# the 86Box commit Tetrium's own fetch script pins must be the one this script builds
grep -q "$BOX_SHA" "$T/tests/fetch.sh" || { echo "lockstep: Tetrium's tests/fetch.sh pins another 86Box commit"; exit 1; }

B="$T/ref/86box"
if [[ ! -d "$B/.git" ]]; then
    rm -rf "$B"
    mkdir -p "$T/ref"
    echo "lockstep: cloning 86Box from $BOX_URL"
    git clone -q --filter=blob:none --no-checkout "$BOX_URL" "$B"
fi
git -C "$B" cat-file -e "$BOX_SHA^{commit}" 2>/dev/null || git -C "$B" fetch -q origin
# (a clean tree at the pinned commit: Tetrium's build.sh applies its 486 patch to it)
git -C "$B" -c advice.detachedHead=false checkout -q --force "$BOX_SHA"
git -C "$B" clean -q -fdx

rm -f "$STAMP"
echo "lockstep: building libx86ref (86Box i486SX interpreter, $JOBS jobs)"
"$T/tb/x86ref/build.sh" "$JOBS"
[[ -f "$LIB" ]] || { echo "lockstep: $LIB was not built"; exit 1; }
echo "$WANT" > "$STAMP"
