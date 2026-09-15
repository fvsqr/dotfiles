# The `code` CLI ships inside the app bundle, whose location depends on
# where casks were installed on this machine.
for __dir in \
  "${HOMEBREW_PREFIX:-/opt/homebrew}/apps" \
  "$HOME/app/homebrew" \
  "$HOME/Applications" \
  /Applications
do
  __bin="$__dir/Visual Studio Code.app/Contents/Resources/app/bin"
  if [[ -d $__bin ]]
  then
    export PATH="$__bin:$PATH"
    break
  fi
done
unset __dir __bin
