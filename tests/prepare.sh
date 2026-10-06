#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$SCRIPT_DIR/singlestep_real"
REAL_MODE_DIR="$DEST_DIR/v1_ex_real_mode"
REPO_URL="https://github.com/SingleStepTests/80386.git"
PROTECTED_DEST_DIR="$SCRIPT_DIR/singlestep_protected"
PROTECTED_REPO_URL="https://github.com/nand2mario/SingleStepTests_80386_protected.git"

if [[ ! -d "$DEST_DIR/.git" ]]; then
    rm -rf "$DEST_DIR"
    git clone "$REPO_URL" "$DEST_DIR"
fi

if compgen -G "$REAL_MODE_DIR/*.gz" > /dev/null; then
    echo Running gunzip...
    gunzip -f "$REAL_MODE_DIR"/*.gz
fi

if [[ ! -d "$PROTECTED_DEST_DIR/.git" ]]; then
    rm -rf "$PROTECTED_DEST_DIR"
    git clone "$PROTECTED_REPO_URL" "$PROTECTED_DEST_DIR"
fi

# test386.asm (make test-386): build a 486 configuration of the upstream
# source.  CPU_FAMILY=4 selects the i486 results for the family-dependent
# tests; OUT_PORT=0xE8 sends the POST 0xEE result lines to the port
# tb_test386.sv prints (byte lane 0), and test386.py compares them with
# test386-EE-reference.txt.  NASM 3 rejects `mov [mem], word imm`; the build
# copy rewrites it to the equivalent `mov word [mem], imm`.
T386_DIR="$SCRIPT_DIR/test386.asm"
T386_REPO_URL="https://github.com/barotto/test386.asm.git"
if [[ ! -d "$T386_DIR/.git" ]]; then
    rm -rf "$T386_DIR"
    git clone "$T386_REPO_URL" "$T386_DIR"
fi
rm -rf "$T386_DIR/build486"
cp -r "$T386_DIR/src" "$T386_DIR/build486"
sed -i 's/^CPU_FAMILY equ .*/CPU_FAMILY equ 4/; s/^OUT_PORT equ .*/OUT_PORT equ 0xE8/' \
    "$T386_DIR/build486/configuration.asm"
sed -i -E 's/\b(mov\s+)(\[[^]]*\])\s*,\s*(byte|word|dword)\s+/\1\3 \2, /' \
    "$T386_DIR"/build486/*.asm "$T386_DIR"/build486/tests/*.asm
nasm -i"$T386_DIR/build486/" -f bin "$T386_DIR/build486/test386.asm" -w-all \
    -o "$T386_DIR/test386.bin"

echo Test data preparation done.