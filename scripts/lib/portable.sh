# Helpers that behave the same on Linux (GNU) and macOS (BSD) userlands.
# Source this file; it defines functions only.

# sha256_file <path>: print the SHA-256 digest of a file.
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# iso_utc_offset <seconds>: print the time <seconds> from now (negative for the
# past) as an RFC 3339 UTC timestamp.
iso_utc_offset() {
  local t=$(( $(date -u +%s) + $1 ))
  date -u -d "@$t" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "$t" +%Y-%m-%dT%H:%M:%SZ
}

# require_tools <tool>...: exit with status 2 if any tool is missing.
require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 2; }
  done
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    echo "missing required tool: sha256sum or shasum" >&2
    exit 2
  fi
}
