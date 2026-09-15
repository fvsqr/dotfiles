#!/bin/bash
#
# Pin selected packages to prevent long-running updates.
# Only pins what is actually installed, so a trimmed Brewfile
# does not abort the installer.

for formula in colima ffmpeg fastfetch
do
  if brew list --formula --versions "$formula" >/dev/null 2>&1
  then
    brew pin "$formula"
  else
    echo "  skipping pin: $formula is not installed"
  fi
done
