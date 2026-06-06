#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swift_schema="$repo_root/app/Sources/GunkApp/Store/Schema.swift"
mcp_schema_v2="$repo_root/mcp/src/schema/v2.sql"
mcp_schema_v3="$repo_root/mcp/src/schema/v3.sql"
mcp_schema_v4="$repo_root/mcp/src/schema/v4.sql"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

awk '
  /\/\/ schema:v2:begin/ { in_block = 1; next }
  /\/\/ schema:v2:end/ { in_block = 0 }
  in_block { print }
' "$swift_schema" |
  sed '1d;$d' > "$tmp_dir/swift-v2.sql"

if ! diff -u "$mcp_schema_v2" "$tmp_dir/swift-v2.sql"; then
  echo "Schema parity check failed: Schema.v2 must match mcp/src/schema/v2.sql byte-for-byte." >&2
  exit 1
fi

awk '
  /\/\/ schema:v3:begin/ { in_block = 1; next }
  /\/\/ schema:v3:end/ { in_block = 0 }
  in_block { print }
' "$swift_schema" |
  sed '1d;$d' > "$tmp_dir/swift-v3.sql"

if ! diff -u "$mcp_schema_v3" "$tmp_dir/swift-v3.sql"; then
  echo "Schema parity check failed: Schema.v3 must match mcp/src/schema/v3.sql byte-for-byte." >&2
  exit 1
fi

awk '
  /\/\/ schema:v4:begin/ { in_block = 1; next }
  /\/\/ schema:v4:end/ { in_block = 0 }
  in_block { print }
' "$swift_schema" |
  sed '1d;$d' > "$tmp_dir/swift-v4.sql"

if ! diff -u "$mcp_schema_v4" "$tmp_dir/swift-v4.sql"; then
  echo "Schema parity check failed: Schema.v4 must match mcp/src/schema/v4.sql byte-for-byte." >&2
  exit 1
fi

# The TS engine writes the same SQLite store and carries its own copy of the
# migrations; keep them byte-for-byte identical to the MCP source of truth.
for version in v0 v1 v2 v3 v4; do
  mcp_file="$repo_root/mcp/src/schema/$version.sql"
  engine_file="$repo_root/engine/src/store/schema/$version.sql"
  if [ ! -f "$engine_file" ]; then
    echo "Schema parity check failed: missing $engine_file." >&2
    exit 1
  fi
  if ! diff -u "$mcp_file" "$engine_file"; then
    echo "Schema parity check failed: engine/src/store/schema/$version.sql must match mcp/src/schema/$version.sql byte-for-byte." >&2
    exit 1
  fi
done

echo "Schema parity check passed."
