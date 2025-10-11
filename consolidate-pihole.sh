#!/usr/bin/env bash
set -euo pipefail

# Consolidate Pi-hole blocking lists from a list of sources (URLs or local files).
# Usage:
#   ./consolidate-pihole.sh sources.txt output.txt
#
# Notes:
# - Reads sources.txt (one URL/path per line, '#' comments and blank lines allowed).
# - Downloads each list (with curl --compressed), extracts domains, de-duplicates,
#   and writes a Pi-hole compatible hosts file (0.0.0.0 domain) to output.txt.
# - Designed to handle large lists efficiently using sort -u.
# - Compatible with the default macOS Bash (3.2).
#
# Domain filtering:
# - Discards non-domain strings (e.g., GUID/hash-like tokens, labels starting/ending with '-').
# - Requires at least one dot and valid DNS label structure: labels are alphanumeric with optional
#   internal hyphens, but cannot start or end with a hyphen.

if [ $# -lt 2 ]; then
  echo "Usage: $0 <sources_file> <output_file>" >&2
  exit 1
fi

sources_file="$1"
output_file="$2"

if [ ! -f "$sources_file" ]; then
  echo "Sources file not found: $sources_file" >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Clean sources (remove comments/blank lines) to a temp file
grep -Ev '^[[:space:]]*(#|$)' "$sources_file" > "$tmpdir/sources_clean.txt" || true

if [ ! -s "$tmpdir/sources_clean.txt" ]; then
  echo "No sources found in $sources_file" >&2
  exit 3
fi

# Fetch/copy each source into tmpdir
idx=0
while IFS= read -r src; do
  idx=$((idx+1))
  dest="$tmpdir/list_$idx.txt"
  case "$src" in
    http://*|https://*)
      echo "Fetching: $src"
      if ! curl -sSL --fail --compressed "$src" -o "$dest"; then
        echo "Warning: failed to fetch $src" >&2
      fi
      ;;
    *)
      if [ -f "$src" ]; then
        cp "$src" "$dest" || echo "Warning: failed to copy $src" >&2
      else
        echo "Warning: source not found: $src" >&2
      fi
      ;;
  esac
done < "$tmpdir/sources_clean.txt"

# Gather fetched lists
shopt -s nullglob
lists=( "$tmpdir"/list_*.txt )
if [ ${#lists[@]} -eq 0 ]; then
  echo "No lists were successfully retrieved." >&2
  exit 4
fi

# Concatenate and extract domains with strict validation
cat "${lists[@]}" | \
awk '
  BEGIN {
    FS="[ \t]+"
    # Precompile regex in variables (POSIX awk compatible on macOS)
    label  = "[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?"
    domrx  = "^" label "(\\." label ")+" "$"
  }
  {
    gsub(/\r/,"",$0)                               # strip CRs
    sub(/^[ \t]+/,"",$0); sub(/[ \t]+$/,"",$0)     # trim
    sub(/[ \t]*#.*/,"",$0)                         # strip inline comments
  }
  $0=="" { next }
  {
    ip=$1
    start=1
    if (ip=="0.0.0.0" || ip=="127.0.0.1" || ip=="::" || ip=="::1") {
      start=2
    }
    for (i=start; i<=NF; i++) {
      host=$i
      gsub(/^\.+|\.+$/,"", host)                   # strip leading/trailing dots

      # Basic rejects
      if (host=="") continue
      if (host ~ /[\/:]/) continue                 # skip things with / or : (URLs, ports)
      if (host ~ /^(localhost|localdomain|broadcasthost)$/) continue
      if (host ~ /\*|\@/) continue                 # wildcards or email-like

      # Strict domain validation (requires at least one dot, labels with optional internal hyphens)
      if (host !~ domrx) continue

      # Lowercase and print
      # (BusyBox awk lacks tolower in some builds, but macOS awk has it.)
      print tolower(host)
    }
  }
' | LC_ALL=C sort -u > "$tmpdir/domains.txt"

# Write out as hosts format
{
  printf "# Consolidated Pi-hole hosts generated on %s\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf "# Sources:\n"
  awk '{ print "# " $0 }' "$tmpdir/sources_clean.txt"
  awk '{ print "0.0.0.0 " $0 }' "$tmpdir/domains.txt"
} > "$output_file"

count="$(wc -l < "$tmpdir/domains.txt" | tr -d ' ')"
echo "Wrote $count unique domains to: $output_file"
