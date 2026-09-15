#!/bin/sh
#
# Bring Homebrew into the current shell, wherever it lives on this machine.
#
# A prefix inside $HOME wins over the system one: on Macs without admin
# rights that is the only place Homebrew can live, and where it exists it
# was put there on purpose.
#
# Override the location by exporting HOMEBREW_USER_PREFIX before sourcing.

: "${HOMEBREW_USER_PREFIX:=$HOME/.homebrew}"

for __brew in \
  "$HOMEBREW_USER_PREFIX/bin/brew" \
  /opt/homebrew/bin/brew \
  /usr/local/bin/brew \
  /home/linuxbrew/.linuxbrew/bin/brew
do
  if [ -x "$__brew" ]
  then
    eval "$("$__brew" shellenv)"
    break
  fi
done
unset __brew

# Casks: if Homebrew lives under $HOME then /Applications is not writable
# either, so keep the app bundles next to the prefix.
case "${HOMEBREW_PREFIX:-}" in
  "$HOME"/*)
    export HOMEBREW_CASK_OPTS="--appdir=$HOMEBREW_PREFIX/apps"
    ;;
esac
