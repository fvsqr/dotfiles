#!/usr/bin/env bash
#
# yt-dlp
#
# Installs the official, prebuilt yt-dlp binary instead of the Homebrew
# formula. The formula pulls in Python and friends, which have to be compiled
# wherever Homebrew has no bottles (Intel, or a prefix inside $HOME). The
# release binary is self-contained and universal (arm64 + x86_64).
#
#   first run   download the latest release, verify its SHA-256, install it
#   later runs  `yt-dlp -U`, which checks GitHub and replaces itself if needed
#
# script/install runs this on every `dot` and `dot update`, so yt-dlp stays
# current without any extra step.
#
# A network failure only prints a warning - it must never abort the rest of
# the installers.

set -uo pipefail

BIN_DIR="$HOME/.local/bin"
TARGET="$BIN_DIR/yt-dlp"
BASE_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download"

case "$(uname -s)" in
  Darwin) ASSET="yt-dlp_macos" ;;
  Linux)
    case "$(uname -m)" in
      x86_64)        ASSET="yt-dlp_linux" ;;
      aarch64|arm64) ASSET="yt-dlp_linux_aarch64" ;;
      *) echo "  yt-dlp: no prebuilt binary for $(uname -m), skipping."; exit 0 ;;
    esac
    ;;
  *) echo "  yt-dlp: unsupported OS $(uname -s), skipping."; exit 0 ;;
esac

sha256 () {
  if command -v shasum >/dev/null 2>&1
  then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

# An old Homebrew copy would shadow or confuse the binary, so point it out.
if command -v brew >/dev/null 2>&1 && brew list --formula yt-dlp >/dev/null 2>&1
then
  echo "  yt-dlp: the Homebrew formula is still installed."
  echo "          Remove it with:  brew uninstall yt-dlp && brew autoremove"
fi

if [ -x "$TARGET" ]
then
  echo "› yt-dlp -U"
  "$TARGET" -U || echo "  yt-dlp: update check failed, keeping $("$TARGET" --version)."
  exit 0
fi

echo "› installing yt-dlp ($ASSET) into $BIN_DIR"
mkdir -p "$BIN_DIR"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/yt-dlp.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

if ! curl -fsSL -o "$tmp/$ASSET"     "$BASE_URL/$ASSET" \
   || ! curl -fsSL -o "$tmp/SHA2-256SUMS" "$BASE_URL/SHA2-256SUMS"
then
  echo "  yt-dlp: download failed, skipping. Run script/install again later."
  exit 0
fi

expected="$(awk -v f="$ASSET" '$2 == f {print $1}' "$tmp/SHA2-256SUMS")"
actual="$(sha256 "$tmp/$ASSET")"
if [ -z "$expected" ] || [ "$expected" != "$actual" ]
then
  echo "  yt-dlp: checksum mismatch, not installing." >&2
  exit 0
fi

chmod +x "$tmp/$ASSET"
mv -f "$tmp/$ASSET" "$TARGET"
echo "  yt-dlp $("$TARGET" --version) installed."
