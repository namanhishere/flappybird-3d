#!/usr/bin/env bash
# Reproducible toolchain setup for the Godot 4 Flappy Bird project.
#
# Downloads a pinned Godot 4.x editor binary and the matching x86_64 Linux
# export templates into a versioned cache directory outside the repository,
# verifying the SHA512 checksums published by the Godot project.
# Idempotent: a cache entry that already matches its pinned checksum is not
# re-downloaded.
#
# Nothing is written inside the repository, no system package is installed, and
# no path outside the cache root below is touched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/toolchain.env
source "${SCRIPT_DIR}/toolchain.env"

log() { printf '[setup] %s\n' "$*"; }
die() { printf '[setup] ERROR: %s\n' "$*" >&2; exit 1; }

for tool in curl unzip sha512sum cut; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done

verify_sha512() {
  local file="$1" expected="$2" actual
  [ -f "$file" ] || return 1
  actual="$(sha512sum "$file" | cut -d' ' -f1)"
  [ "$actual" = "$expected" ]
}

download() {
  local url="$1"
  local dest="$2"
  local expected="$3"
  local tmp="${dest}.part"
  mkdir -p "$(dirname "$dest")"
  if verify_sha512 "$dest" "$expected"; then
    log "cached and verified: $(basename "$dest")"
    return 0
  fi
  log "downloading $(basename "$dest") (large file, please wait)..."
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 -o "$tmp" "$url" \
    || die "download failed: $url"
  if ! verify_sha512 "$tmp" "$expected"; then
    rm -f "$tmp"
    die "checksum mismatch for $(basename "$dest")
  Expected SHA512: $expected
  The file downloaded from the official release URL did not match the pin, so
  the toolchain would be corrupt. Refusing to continue."
  fi
  mv "$tmp" "$dest"
  log "verified: $(basename "$dest")"
}

mkdir -p "$CACHE_ROOT" "$GODOT_DATA_DIR"

# --- 1. editor binary --------------------------------------------------------
if [ -x "$GODOT_BIN" ] && "$GODOT_BIN" --version 2>/dev/null | grep -q "$GODOT_VERSION"; then
  log "godot $GODOT_VERSION already installed"
else
  download "${GODOT_RELEASE_BASE}/${GODOT_ZIP}" "${DOWNLOAD_DIR}/${GODOT_ZIP}" "$GODOT_ZIP_SHA512"
  rm -rf "${CACHE_ROOT}/bin"
  mkdir -p "${CACHE_ROOT}/bin"
  unzip -q -o "${DOWNLOAD_DIR}/${GODOT_ZIP}" \
    "Godot_v${GODOT_TAG}_linux.x86_64" -d "${CACHE_ROOT}/bin" \
    || die "failed to extract editor binary"
  mv "${CACHE_ROOT}/bin/Godot_v${GODOT_TAG}_linux.x86_64" "$GODOT_BIN"
  chmod +x "$GODOT_BIN"
  log "installed editor binary"
fi

"$GODOT_BIN" --version >/dev/null 2>&1 \
  || die "binary at $GODOT_BIN will not run on this machine"

# --- 2. export templates (x86_64 Linux only) ---------------------------------
if [ -f "${TEMPLATE_DIR}/linux_release.x86_64" ] \
   && [ -f "${TEMPLATE_DIR}/linux_debug.x86_64" ]; then
  log "export templates already installed"
else
  download "${GODOT_RELEASE_BASE}/${GODOT_TPZ}" "${DOWNLOAD_DIR}/${GODOT_TPZ}" "$GODOT_TPZ_SHA512"
  log "extracting x86_64 Linux export templates from the 1.3 GB archive..."
  rm -rf "$TEMPLATE_DIR"
  mkdir -p "$TEMPLATE_DIR"
  # -j flattens the archive's templates/ prefix, which is the layout Godot expects.
  unzip -q -j -o "${DOWNLOAD_DIR}/${GODOT_TPZ}" \
    'templates/linux_debug.x86_64' \
    'templates/linux_release.x86_64' \
    -d "$TEMPLATE_DIR" \
    || die "failed to extract export templates"
  [ -f "${TEMPLATE_DIR}/linux_release.x86_64" ] \
    || die "archive did not contain templates/linux_release.x86_64"
  rm -f "${DOWNLOAD_DIR}/${GODOT_TPZ}"
  log "installed export templates"
fi

cat <<EOF
[setup] toolchain ready
[setup]   godot binary : $GODOT_BIN
[setup]   templates    : $TEMPLATE_DIR
[setup]   cache root   : $CACHE_ROOT
[setup] Next: 'make test'
EOF
