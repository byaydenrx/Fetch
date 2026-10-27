#!/bin/zsh
# Builds Fetch from source and installs it into ~/Applications.
set -e
cd "$(dirname "$0")"
if [[ $(sw_vers -productVersion | cut -d. -f1) -lt 26 ]]; then
  echo "Fetch needs macOS 26 or later (this Mac has $(sw_vers -productVersion))."; exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift isn't installed. Run: xcode-select --install   (then run this script again)"; exit 1
fi
./build.sh
pkill -x Fetch 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/Fetch.app
cp -R build/Fetch.app ~/Applications/
echo "Installed ~/Applications/Fetch.app"
if ! command -v aria2c >/dev/null && [[ ! -x /opt/homebrew/bin/aria2c && ! -x /usr/local/bin/aria2c && ! -x /opt/local/bin/aria2c ]]; then
  echo "Fetch needs aria2c. Install it with: brew install aria2"
fi
open ~/Applications/Fetch.app
