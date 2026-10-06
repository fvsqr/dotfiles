#!/usr/bin/env bash
#
# deno
#
# yt-dlp needs a JavaScript runtime to solve YouTube's challenges, and deno
# is the one it uses by default. Installed from the official prebuilt
# release instead of Homebrew, like yt-dlp and ffmpeg.
#
#   first run   download the latest release, verify its SHA-256, install it
#   later runs  `deno upgrade`, which replaces the binary in place
#
# script/install runs this on every `dot` and `dot update`.
#
# A network failure only prints a warning - it must never abort the rest of
# the installers.

set -uo pipefail

BIN_DIR="$HOME/.local/bin"
TARGET="$BIN_DIR/deno"
BASE_URL="https://github.com/denoland/deno/releases/latest/download"

case "$(uname -s)" in
  Darwin)
    # The real hardware, even inside a Rosetta shell.
    if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]
    then
      ASSET="deno-aarch64-apple-darwin.zip"
    else
      ASSET="deno-x86_64-apple-darwin.zip"
    fi
    ;;
  Linux)
    case "$(uname -m)" in
      x86_64)        ASSET="deno-x86_64-unknown-linux-gnu.zip" ;;
      aarch64|arm64) ASSET="deno-aarch64-unknown-linux-gnu.zip" ;;
      *) echo "  deno: no prebuilt binary for $(uname -m), skipping."; exit 0 ;;
    esac
    ;;
  *) echo "  deno: unsupported OS $(uname -s), skipping."; exit 0 ;;
esac

sha256 () {
  if command -v shasum >/dev/null 2>&1
  then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

if command -v brew >/dev/null 2>&1 && brew list --formula deno >/dev/null 2>&1
then
  echo "  deno: the Homebrew formula is still installed."
  echo "        Remove it with:  brew uninstall deno && brew autoremove"
fi

if [ -x "$TARGET" ]
then
  echo "› deno upgrade"
  "$TARGET" upgrade --quiet \
    || echo "  deno: upgrade failed, keeping $("$TARGET" --version | head -n1)."
  exit 0
fi

echo "› installing deno ($ASSET) into $BIN_DIR"
mkdir -p "$BIN_DIR"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/deno.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

if ! curl -fsSL -o "$tmp/$ASSET"           "$BASE_URL/$ASSET" \
   || ! curl -fsSL -o "$tmp/$ASSET.sha256sum" "$BASE_URL/$ASSET.sha256sum"
then
  echo "  deno: download failed, skipping. Run script/install again later."
  exit 0
fi

expected="$(grep -oE '[0-9a-fA-F]{64}' "$tmp/$ASSET.sha256sum" | head -n1 | tr 'A-F' 'a-f')"
actual="$(sha256 "$tmp/$ASSET")"
if [ -z "$expected" ] || [ "$expected" != "$actual" ]
then
  echo "  deno: checksum mismatch, not installing." >&2
  exit 0
fi

unzip -q -o "$tmp/$ASSET" -d "$tmp/out"
chmod +x "$tmp/out/deno"
mv -f "$tmp/out/deno" "$TARGET"
echo "  $("$TARGET" --version | head -n1) installed."
