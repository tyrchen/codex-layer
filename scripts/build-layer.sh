#!/usr/bin/env bash
# build-layer.sh - Assemble the Codex CLI Lambda Layer
#
# Reads assets.yaml and downloads/extracts all declared assets into a layer ZIP.
# Works both locally (macOS/Linux with Docker) and in GitHub Actions.
#
# Environment variables:
#   LAYER_DIR   - staging directory  (default: /tmp/codex-layer)
#   LAYER_ZIP   - output ZIP path    (default: /tmp/codex-layer.zip)
#   GH_TOKEN    - GitHub token for cross-repo artifact download
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_FILE="$ROOT_DIR/assets.yaml"

LAYER_DIR="${LAYER_DIR:-/tmp/codex-layer}"
LAYER_ZIP="${LAYER_ZIP:-/tmp/codex-layer.zip}"
CONTAINER_RT="${CONTAINER_RT:-$(command -v docker 2>/dev/null || command -v podman 2>/dev/null || true)}"

# ── Pre-flight checks ───────────────────────────────────────────────────────
for cmd in yq gh curl zip; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is required but not found in PATH" >&2
    exit 1
  fi
done

if [ ! -f "$ASSETS_FILE" ]; then
  echo "ERROR: $ASSETS_FILE not found" >&2
  exit 1
fi

# ── Prepare staging directory ────────────────────────────────────────────────
rm -rf "$LAYER_DIR" "$LAYER_ZIP"
mkdir -p "$LAYER_DIR"/{bin,lib,libexec}

# ── 1. Codex binary from tyrchen/codex ───────────────────────────────────────
CODEX_REPO=$(yq '.codex.repo' "$ASSETS_FILE")
CODEX_ARTIFACT=$(yq '.codex.artifact' "$ASSETS_FILE")
CODEX_TAR=$(yq '.codex.tar_file' "$ASSETS_FILE")
CODEX_BIN=$(yq '.codex.bin_name' "$ASSETS_FILE")

echo "==> Downloading $CODEX_BIN from $CODEX_REPO"
gh run download --repo "$CODEX_REPO" --name "$CODEX_ARTIFACT" --dir /tmp/codex-artifact
tar xzf "/tmp/codex-artifact/$CODEX_TAR" -C "$LAYER_DIR/bin/"
# The tarball contains a single file named codex-aarch64-unknown-linux-musl
if [ -f "$LAYER_DIR/bin/codex-aarch64-unknown-linux-musl" ]; then
  mv "$LAYER_DIR/bin/codex-aarch64-unknown-linux-musl" "$LAYER_DIR/bin/$CODEX_BIN"
fi
chmod +x "$LAYER_DIR/bin/$CODEX_BIN"
rm -rf /tmp/codex-artifact
ls -lh "$LAYER_DIR/bin/$CODEX_BIN"

# ── 2. GitHub Release tools ─────────────────────────────────────────────────
TOOL_COUNT=$(yq '.tools | length' "$ASSETS_FILE")
for i in $(seq 0 $((TOOL_COUNT - 1))); do
  NAME=$(yq ".tools[$i].name" "$ASSETS_FILE")
  REPO=$(yq ".tools[$i].repo" "$ASSETS_FILE")
  VERSION=$(yq ".tools[$i].version" "$ASSETS_FILE")
  ASSET_TPL=$(yq ".tools[$i].asset" "$ASSETS_FILE")
  TAG_TPL=$(yq ".tools[$i].tag // \"\"" "$ASSETS_FILE")
  STRIP=$(yq ".tools[$i].strip // \"0\"" "$ASSETS_FILE")
  EXTRACT_PATH_TPL=$(yq ".tools[$i].extract_path // \"\"" "$ASSETS_FILE")

  # Expand {version} placeholders
  ASSET="${ASSET_TPL//\{version\}/$VERSION}"
  EXTRACT_PATH="${EXTRACT_PATH_TPL//\{version\}/$VERSION}"

  if [ -n "$TAG_TPL" ] && [ "$TAG_TPL" != "null" ]; then
    TAG="${TAG_TPL//\{version\}/$VERSION}"
  else
    TAG="v$VERSION"
  fi

  URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"
  echo "==> Downloading $NAME $VERSION from $REPO"

  if [[ "$ASSET" == *.tar.gz ]] || [[ "$ASSET" == *.tgz ]]; then
    if [ -n "$EXTRACT_PATH" ] && [ "$EXTRACT_PATH" != "null" ]; then
      curl -sL "$URL" | tar xz --strip-components="$STRIP" -C "$LAYER_DIR/bin/" "$EXTRACT_PATH"
    elif [ "$STRIP" != "0" ]; then
      curl -sL "$URL" | tar xz --strip-components="$STRIP" -C "$LAYER_DIR/bin/"
    else
      curl -sL "$URL" | tar xz -C "$LAYER_DIR/bin/"
    fi
  else
    curl -sL -o "$LAYER_DIR/bin/$NAME" "$URL"
  fi

  chmod +x "$LAYER_DIR/bin/$NAME"
  ls -lh "$LAYER_DIR/bin/$NAME"
done

# ── 3. System packages from Amazon Linux 2023 ───────────────────────────────
if [ -z "$CONTAINER_RT" ]; then
  echo "WARNING: No container runtime (docker/podman) found, skipping system packages" >&2
else
  PLATFORM=$(yq '.platform' "$ASSETS_FILE")

  # Build the dnf + copy command
  PACKAGES=$(yq '.system.packages[]' "$ASSETS_FILE" | tr '\n' ' ')
  CMD="dnf install -y $PACKAGES"

  while IFS= read -r bin; do
    CMD+=" && cp /usr/bin/$bin /out/bin/$bin"
  done < <(yq '.system.bins[]' "$ASSETS_FILE")

  while IFS= read -r le; do
    [ "$le" = "null" ] && continue
    CMD+=" && (cp -a /usr/libexec/$le /out/libexec/ 2>/dev/null || true)"
  done < <(yq '.system.libexec[]' "$ASSETS_FILE" 2>/dev/null || true)

  while IFS= read -r lib; do
    [ "$lib" = "null" ] && continue
    CMD+=" && find /usr/lib64 -name \"$lib\" -exec cp {} /out/lib/ \\;"
  done < <(yq '.system.libs[]' "$ASSETS_FILE" 2>/dev/null || true)

  echo "==> Extracting system packages from AL2023"
  $CONTAINER_RT run --rm --platform "$PLATFORM" \
    -v "$LAYER_DIR:/out" \
    public.ecr.aws/amazonlinux/amazonlinux:2023 \
    bash -c "$CMD"
fi

# ── 4. Build ZIP ────────────────────────────────────────────────────────────
echo "==> Building layer ZIP"
cd "$LAYER_DIR"
zip --symlinks -r "$LAYER_ZIP" bin/ lib/ libexec/

echo ""
echo "==> Layer contents:"
ls -lh "$LAYER_DIR/bin/"
echo ""
ls -lh "$LAYER_DIR/lib/" 2>/dev/null || echo "    (no libs)"
echo ""
echo "==> Layer ZIP: $LAYER_ZIP"
du -sh "$LAYER_ZIP"
