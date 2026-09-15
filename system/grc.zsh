# GRC colorizes nifty unix tools all over the place
if (( $+commands[grc] )) && [[ -n $HOMEBREW_PREFIX ]]
then
  [[ -f $HOMEBREW_PREFIX/etc/grc.bashrc ]] && source $HOMEBREW_PREFIX/etc/grc.bashrc
fi
