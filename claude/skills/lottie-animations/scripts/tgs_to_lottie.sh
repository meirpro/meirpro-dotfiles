#!/usr/bin/env bash
# tgs_to_lottie.sh — convert Telegram .tgs files to Lottie JSON
#
# A .tgs file is a gzipped Lottie JSON with a "tgs": 1 marker at the
# root. This script unzips it. That is the entire conversion.
#
# Usage:
#   tgs_to_lottie.sh input.tgs > output.json
#   tgs_to_lottie.sh --batch input_dir/ output_dir/
#
# In batch mode: every *.tgs in input_dir/ becomes the same basename .json
# in output_dir/. output_dir/ is created if missing. Existing .json files
# are overwritten without prompting.

set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

convert_one() {
  local input="$1"
  [[ -f "$input" ]] || die "Not a file: $input"

  # Sanity-check it's actually gzip. Magic bytes 1f 8b.
  local magic
  magic=$(head -c 2 "$input" | od -An -tx1 | tr -d ' \n')
  [[ "$magic" == "1f8b" ]] || die "Not a gzip stream (no 1f 8b magic): $input"

  gunzip -c "$input"
}

if [[ $# -eq 0 ]]; then
  usage
fi

if [[ "$1" == "--batch" ]]; then
  [[ $# -eq 3 ]] || die "Batch mode: tgs_to_lottie.sh --batch in_dir/ out_dir/"
  in_dir="$2"
  out_dir="$3"
  [[ -d "$in_dir" ]] || die "Not a directory: $in_dir"
  mkdir -p "$out_dir"

  count=0
  shopt -s nullglob
  for tgs in "$in_dir"/*.tgs; do
    base=$(basename "$tgs" .tgs)
    convert_one "$tgs" > "$out_dir/$base.json"
    count=$((count + 1))
  done
  echo "Converted $count file(s) to $out_dir/" >&2
  exit 0
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi

[[ $# -eq 1 ]] || die "Single-file mode takes exactly one argument. Use --batch for directories."
convert_one "$1"
