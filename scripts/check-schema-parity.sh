#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swift_schema="$repo_root/app/Sources/GunkApp/Store/Schema.swift"
mcp_schema="$repo_root/mcp/src/schema/v2.sql"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

awk '
  /\/\/ schema:v2:begin/ { in_block = 1; next }
  /\/\/ schema:v2:end/ { in_block = 0 }
  in_block { print }
' "$swift_schema" |
  sed '1d;$d' > "$tmp_dir/swift-v2.sql"

if ! diff -u "$mcp_schema" "$tmp_dir/swift-v2.sql"; then
  echo "Schema parity check failed: Schema.v2 must match mcp/src/schema/v2.sql byte-for-byte." >&2
  exit 1
fi

echo "Schema parity check passed."
