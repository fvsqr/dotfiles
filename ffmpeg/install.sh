#!/usr/bin/env bash
#
# ffmpeg
#
# Installs static ffmpeg and ffprobe builds instead of the Homebrew formula,
# which drags in dozens of libraries that have to be compiled wherever
# Homebrew has no bottles (Intel, or a prefix inside $HOME).
#
# Builds come from https://ffmpeg.martin-riedl.de - native arm64 and x86_64
# macOS binaries, signed, with a SHA-256 next to every download. yt-dlp needs
# both ffmpeg (merging) and ffprobe (metadata).
#
# There is no self-update. Instead, the "latest" link is resolved on every run
# to the directory of the current build (e.g. .../1789931006_9.0.2/). Only
# when that differs from the last install is the zip downloaded again, and
# its SHA-256 is checked against the .sha256 file in that same directory.
# (The latest links only exist for the zips, not for the .sha256 files.)
#
# script/install runs this on every `dot` and `dot update`.
#
# A network failure only prints a warning - it must never abort the rest of
# the installers.

set -uo pipefail

BIN_DIR="$HOME/.local/bin"
STATE_DIR="$HOME/.local/share/dotfiles/ffmpeg"
CHANNEL="release"     # or "snapshot" for builds from FFmpeg master

case "$(uname -s)" in
  Darwin) os="macos" ;;
  Linux)  os="linux" ;;
  *) echo "  ffmpeg: unsupported OS $(uname -s), skipping."; exit 0 ;;
esac

# The real hardware, even inside a Rosetta shell.
if [ "$os" = "macos" ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]
then
  arch="arm64"
else
  case "$(uname -m)" in
    x86_64)        arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "  ffmpeg: no prebuilt binary for $(uname -m), skipping."; exit 0 ;;
  esac
fi

BASE_URL="https://ffmpeg.martin-riedl.de/redirect/latest/$os/$arch/$CHANNEL"

sha256 () {
  if command -v shasum >/dev/null 2>&1
  then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

if command -v brew >/dev/null 2>&1 && brew list --formula ffmpeg >/dev/null 2>&1
then
  echo "  ffmpeg: the Homebrew formula is still installed."
  echo "          Remove it with:  brew unpin ffmpeg; brew uninstall ffmpeg && brew autoremove"
fi

mkdir -p "$BIN_DIR" "$STATE_DIR"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ffmpeg.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# install_tool ffmpeg|ffprobe
install_tool () {
  local tool="$1" url dir build stored expected actual binary

  # Follow the latest link one hop to find the directory of the current build.
  url="$(curl -fsS -o /dev/null -w '%{redirect_url}' "$BASE_URL/$tool.zip" 2>/dev/null)"
  if [ -z "$url" ]
  then
    echo "  $tool: could not reach the build server, skipping."
    return 0
  fi
  dir="${url%/*}"
  build="${dir##*/}"          # e.g. 1789931006_9.0.2
  stored="$(cat "$STATE_DIR/$tool.build" 2>/dev/null || true)"

  if [ -x "$BIN_DIR/$tool" ] && [ "$build" = "$stored" ]
  then
    echo "  $tool ${build#*_} is up to date."
    return 0
  fi

  echo "› installing $tool ${build#*_} ($os/$arch) into $BIN_DIR"
  if ! curl -fsSL -o "$tmp/$tool.zip" "$dir/$tool.zip" \
     || ! curl -fsSL -o "$tmp/$tool.zip.sha256" "$dir/$tool.zip.sha256"
  then
    echo "  $tool: download failed, skipping."
    return 0
  fi

  expected="$(grep -oE '[0-9a-fA-F]{64}' "$tmp/$tool.zip.sha256" | head -n1 | tr 'A-F' 'a-f')"
  actual="$(sha256 "$tmp/$tool.zip")"
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]
  then
    echo "  $tool: checksum mismatch, not installing." >&2
    return 0
  fi

  mkdir -p "$tmp/$tool"
  unzip -q -o "$tmp/$tool.zip" -d "$tmp/$tool"
  binary="$(find "$tmp/$tool" -type f -name "$tool" | head -n1)"
  if [ -z "$binary" ]
  then
    echo "  $tool: no binary found in the archive, not installing." >&2
    return 0
  fi

  chmod +x "$binary"
  mv -f "$binary" "$BIN_DIR/$tool"
  printf '%s\n' "$build" > "$STATE_DIR/$tool.build"
  echo "  $("$BIN_DIR/$tool" -version | head -n1)"
}

install_tool ffmpeg
install_tool ffprobe
