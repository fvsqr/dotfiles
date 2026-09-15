#!/usr/bin/env bash
#
# Homebrew
#
# Installs Homebrew into the best prefix this Mac allows:
#
#   Apple Silicon + admin   -> /opt/homebrew via the official installer.
#   Intel        + admin    -> /usr/local, set up by hand. The official
#                              installer refuses to run on Intel, but the
#                              remaining Intel bottles are built for this
#                              prefix, so it is still worth having.
#   anything     + no admin -> $HOMEBREW_USER_PREFIX (default ~/.homebrew),
#                              a plain git clone. Casks go to <prefix>/apps.
#                              Almost everything is built from source.
#
# Homebrew treats Intel macOS as Tier 3: no new bottles are built for it and
# support is slated to end in or after September 2027. Existing bottles keep
# working in /usr/local until then.
#
# Bottles in a custom prefix need the prefix to be no longer in bytes than
# the platform default (/opt/homebrew = 13). ~/.homebrew is longer, so it
# builds from source. If that matters more than a readable path:
#
#   HOMEBREW_USER_PREFIX=~/hb script/install      # and keep it in ~/.localrc
#
# Set HOMEBREW_NO_ADMIN=1 to take the unprivileged path even where admin
# rights exist - useful for testing that path on a machine that has them.

set -euo pipefail

: "${HOMEBREW_USER_PREFIX:=$HOME/.homebrew}"

BREW_REPO_URL="https://github.com/Homebrew/brew"

have_admin_rights () {
  if [ -n "${HOMEBREW_NO_ADMIN:-}" ]
  then
    return 1
  fi

  if [ "$(uname -s)" = "Darwin" ]
  then
    # sudo is available to members of the admin group
    id -Gn 2>/dev/null | tr ' ' '\n' | grep -qx admin
  else
    [ -w /home/linuxbrew ] || [ -w /usr/local ]
  fi
}

# What the machine is, regardless of what this process is translated to:
# hw.optional.arm64 is 1 on Apple Silicon even inside a Rosetta shell.
mac_hardware_is_arm64 () {
  [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]
}

running_under_rosetta () {
  [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]
}

# Will the official installer run here? It aborts unless uname -m is arm64.
official_installer_works () {
  [ "$(uname -s)" = "Darwin" ] || return 0
  mac_hardware_is_arm64
}

require_developer_tools () {
  [ "$(uname -s)" = "Darwin" ] || return 0
  xcode-select -p >/dev/null 2>&1 && return 0

  echo "  Xcode Command Line Tools are missing - Homebrew needs them."
  if have_admin_rights
  then
    echo "  Starting the installer; re-run this script once it has finished."
    xcode-select --install || true
  else
    echo "  Installing them requires admin rights. Ask whoever administers"
    echo "  this Mac to run:  xcode-select --install"
  fi
  return 1
}

# Locate an existing brew without executing it - a broken install refuses to
# run at all, and we still need to know where it lives to repair it.
find_brew () {
  local candidate
  for candidate in \
    "$HOMEBREW_USER_PREFIX/bin/brew" \
    /opt/homebrew/bin/brew \
    /usr/local/bin/brew \
    /home/linuxbrew/.linuxbrew/bin/brew
  do
    if [ -x "$candidate" ]
    then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# The repository is the prefix, except for the /usr/local layout where it
# sits in /usr/local/Homebrew. Resolve symlinks without relying on realpath.
brew_repository () {
  local bin="$1" target
  while [ -L "$bin" ]
  do
    target="$(readlink "$bin")"
    case "$target" in
      /*) bin="$target" ;;
      *)  bin="$(dirname "$bin")/$target" ;;
    esac
  done
  ( cd "$(dirname "$bin")/.." && pwd -P )
}

# The official installer puts the repository on a branch named "stable" at
# the newest tag rather than on main, so that brew tracks releases instead
# of development. Do the same wherever we set a repository up ourselves.
checkout_stable () {
  local repo="$1" tag
  tag="$(git -C "$repo" -c "column.ui=never" tag --list --sort="-version:refname" | head -n1)"
  if [ -n "$tag" ]
  then
    git -C "$repo" checkout --quiet --force -B stable "$tag"
  else
    git -C "$repo" checkout --quiet --force -B main origin/main
  fi
}

# A prefix unpacked from a tarball has no .git, and `brew update` is a git
# fetch - it can never succeed, and brew eventually refuses to run at all.
# Restore the repository in place: Cellar, Caskroom and opt are untracked,
# so every installed package survives.
repair_repository () {
  local repo="$1"

  [ -d "$repo/.git" ] && return 0

  echo "  $repo is not a git repository - restoring it in place."
  git -C "$repo" init -q
  git -C "$repo" remote add origin "$BREW_REPO_URL" 2>/dev/null \
    || git -C "$repo" remote set-url origin "$BREW_REPO_URL"
  git -C "$repo" fetch -q --force origin
  checkout_stable "$repo"

  "$repo/bin/brew" update --force --quiet || true
}

install_system_wide () {
  echo "  Installing Homebrew into the standard prefix."

  if running_under_rosetta
  then
    echo "  This shell runs under Rosetta; installing natively as arm64."
    NONINTERACTIVE=1 arch -arm64 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
}

# Intel + admin. The official installer aborts on Intel, so perform the same
# steps it would: create and hand over the prefix directories, then set the
# repository up in /usr/local/Homebrew and link bin/brew to it.
install_into_usr_local () {
  local prefix=/usr/local
  local repo="$prefix/Homebrew"
  local owner group
  owner="$(id -un)"
  group=admin

  echo "  Intel Mac with admin rights: installing Homebrew into $prefix."
  echo "  The official installer refuses to run on Intel, so this performs"
  echo "  the same steps directly - sudo will ask for your password."

  local names=(bin etc include lib sbin share var opt
               share/zsh share/zsh/site-functions
               var/homebrew var/homebrew/linked
               Cellar Caskroom Frameworks)

  local name dirs=()
  for name in "${names[@]}"
  do
    dirs+=("$prefix/$name")
  done

  sudo mkdir -p "${dirs[@]}"
  sudo chmod ug=rwx "${dirs[@]}"
  sudo chmod go-w "$prefix/share/zsh" "$prefix/share/zsh/site-functions"
  sudo chown "$owner" "${dirs[@]}"
  sudo chgrp "$group" "${dirs[@]}"

  sudo mkdir -p "$repo"
  sudo chown -R "$owner:$group" "$repo"

  git -C "$repo" init -q
  git -C "$repo" config remote.origin.url "$BREW_REPO_URL"
  git -C "$repo" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git -C "$repo" config --bool fetch.prune true
  git -C "$repo" fetch --quiet --force origin
  checkout_stable "$repo"

  ln -sf ../Homebrew/bin/brew "$prefix/bin/brew"
  "$prefix/bin/brew" update --force --quiet
}

install_into_home () {
  if ! official_installer_works
  then
    echo "  Intel Mac without admin rights. Homebrew treats Intel as"
    echo "  unsupported and builds no new bottles for it, so everything"
    echo "  is compiled locally wherever it goes."
  else
    echo "  No admin rights on this Mac."
  fi
  echo "  Installing Homebrew into $HOMEBREW_USER_PREFIX (source builds)."

  # A git clone, never a tarball: brew update is a git fetch.
  git clone -q "$BREW_REPO_URL" "$HOMEBREW_USER_PREFIX"
  checkout_stable "$HOMEBREW_USER_PREFIX"
  "$HOMEBREW_USER_PREFIX/bin/brew" update --force --quiet
}

require_developer_tools

if ! brew_bin="$(find_brew)"
then
  echo "  Installing Homebrew for you."
  if ! have_admin_rights
  then
    install_into_home
  elif official_installer_works
  then
    install_system_wide
  else
    install_into_usr_local
  fi
  brew_bin="$(find_brew)"
fi

repair_repository "$(brew_repository "$brew_bin")"

source "$(dirname "$0")/shellenv.sh"

if ! command -v brew >/dev/null 2>&1
then
  echo "  Homebrew installation failed." >&2
  exit 1
fi

# Somewhere to put cask app bundles when /Applications is off limits.
case "$HOMEBREW_PREFIX" in
  "$HOME"/*) mkdir -p "$HOMEBREW_PREFIX/apps" ;;
esac

# Keep compinit from complaining about group-writable completion dirs.
if [ -d "$HOMEBREW_PREFIX/share/zsh" ]
then
  chmod -R go-w "$HOMEBREW_PREFIX/share/zsh"
fi

source "$(dirname "$0")/pin.sh"
