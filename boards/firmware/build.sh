#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bin_file="$script_dir/blink.bin"
hex_file="$script_dir/blink.hex"

nasm -f bin -o "$bin_file" "$script_dir/blink.asm"

size=$(stat -c '%s' "$bin_file")
if [ "$size" -ne 65536 ]; then
    echo "firmware image is $size bytes, expected 65536" >&2
    exit 1
fi

# z486 returns little-endian DWORDs on its external bus. GNU od emits each
# four-byte group as the corresponding host-independent hexadecimal word on
# the supported little-endian build hosts.
od -An -v -t x4 "$bin_file" | tr -s ' ' '\n' | sed '/^$/d' > "$hex_file"

words=$(wc -l < "$hex_file")
if [ "$words" -ne 16384 ]; then
    echo "firmware hex has $words words, expected 16384" >&2
    exit 1
fi

echo "built $hex_file ($words DWORDs)"
