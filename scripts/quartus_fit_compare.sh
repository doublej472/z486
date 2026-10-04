#!/usr/bin/env bash
# Before/after Quartus fit comparison for a pair of RTL revisions.
#
# The point is to answer "did this change cost timing or logic?" with a number
# instead of an argument, on the *real* project: the register forwarding views
# feed the operand-read and register-write cones, so only the synthesized design
# can say what an extra merge tier costs.
#
# Usage:
#   scripts/quartus_fit_compare.sh path/to/project.qpf [revision]
#
#   revision  git revision to use as the "before" side (default: HEAD).
#             The working tree is the "after" side.
#
# Both sides are fitted from a clean checkout, so uncommitted edits cannot leak
# into the baseline.  Requires quartus_sh / quartus_fit / quartus_sta and a
# Quartus project that consumes the RTL of this repository (for example the
# z486_MiSTer SoC project).
set -uo pipefail

QPF=${1:?usage: $0 path/to/project.qpf [revision]}
REV=${2:-HEAD}
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
WORK=$(mktemp -d /tmp/z486-fit.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

for t in quartus_sh quartus_fit quartus_sta; do
    command -v "$t" >/dev/null || { echo "error: $t not found in PATH"; exit 1; }
done

# RTL files whose difference is under test; reported so a null result can be
# recognised as "the fit did not actually see the change".
FILES=$(git -C "$ROOT" diff --name-only "$REV" -- '*.sv' '*.svh' | tr '\n' ' ')
if [ -z "${FILES// /}" ]; then
    echo "error: no .sv/.svh differences vs $REV to compare"; exit 1
fi
echo "comparing $REV -> working tree, RTL under test:"
git -C "$ROOT" diff --stat "$REV" -- '*.sv' '*.svh' | sed 's/^/  /'
echo

# --- stage both revisions into clean trees -----------------------------------
stage() {          # stage <label> <rev|->
    local label=$1 rev=$2 dst="$WORK/$1"
    mkdir -p "$dst"
    if [ "$rev" = "-" ]; then
        # Working tree, minus build and simulator output.
        (cd "$ROOT" && git ls-files -co --exclude-standard) | grep -vE '^tests/(obj_dir|.*\.hex)' |
            while read -r f; do
                [ -f "$ROOT/$f" ] || continue
                mkdir -p "$dst/$(dirname "$f")"; cp "$ROOT/$f" "$dst/$f"
            done
    else
        git -C "$ROOT" archive "$rev" | tar -x -C "$dst"
    fi
    echo "$dst"
}

BASE=$(stage base "$REV")
NEW=$(stage new -)

# The .qpf lives outside the repo for the MiSTer build, so copy it in and let
# Quartus resolve the RTL from each staged tree.
for d in "$BASE" "$NEW"; do
    mkdir -p "$d/prj"
    cp "$QPF" "$d/prj/" 2>/dev/null
    qsf=$(dirname "$QPF")/$(basename "$QPF" .qpf).qsf
    [ -f "$qsf" ] && cp "$qsf" "$d/prj/"
done

# --- fit ---------------------------------------------------------------------
run_fit() {        # run_fit <label> <dir>
    local label=$1 dir=$2 log="$WORK/$label.log"
    ( cd "$dir" && quartus_sh --flow fit prj/$(basename "$QPF") \
        --parallel $(nproc) >"$log" 2>&1 )
    if [ $? -ne 0 ]; then
        echo "  $label: FIT FAILED (see $log)"; return 1
    fi
}

echo "fitting baseline ($REV) ..."; run_fit base "$BASE"; b=$?
echo "fitting working tree ...";     run_fit new  "$NEW";  n=$?
[ $b -ne 0 ] || [ $n -ne 0 ] && { echo "one or both fits failed"; exit 1; }

# --- report ------------------------------------------------------------------
metrics() {        # metrics <dir>
    local dir=$1 rpt
    rpt=$(find "$dir" -name "*.fit.summary" | head -1)
    sta=$(find "$dir" -name "*.sta.rpt" | head -1)
    if [ -n "$rpt" ]; then
        grep -E "Total logic elements|Total registers|Total memory bits|Total block memory bits|Total pins" "$rpt" \
            | sed 's/:.*[[:space:]]\([0-9][0-9,]*\).*/| \1/' | tr -d ' ' | tr '\n' ' '
    fi
    if [ -n "$sta" ]; then
        # Worst-case slack of the slow model, the number that decides whether
        # the design still closes.
        awk '/Worst-case Slack/{f=1} f && /slow 1100mV|slow model|Worst-case Slack/{print; if (++c==2) exit}' "$sta" \
            | grep -oE '[-]?[0-9]+\.[0-9]+' | head -1 | sed 's/^/worst_slack|/'
    fi
}

printf "%-28s %14s %14s %10s\n" metric baseline working delta
printf "%-28s %14s %14s %10s\n" "-----------------------------" "--------" "-------" "-----"
paste <(metrics "$BASE" | tr ' ' '\n') <(metrics "$NEW" | tr ' ' '\n') |
    while IFS=$'\t' read -r left right; do
        bl=${left#*|}; rv=${right#*|}
        name=${left%%|*}
        if [[ "$bl" =~ ^[0-9,]+$ ]] && [[ "$rv" =~ ^[0-9,]+$ ]]; then
            printf "%-28s %14s %14s %10s\n" "$name" "$bl" "$rv" \
                "$(( ${bl//,/} - ${rv//,/} ))"
        fi
    done

echo
echo "Full reports are under $WORK (not deleted on failure paths if you re-run)."
echo "Also worth reading by hand: the worst-case register-to-register path in"
echo "each *.sta.rpt, filtered on gpr_write_merge, to see whether the merge is"
echo "now on the critical path at all."
