#!/bin/bash
# Installs the latest Cut release, signed on your Mac. No Xcode, no Apple Developer account.
#
#   curl -fsSL https://raw.githubusercontent.com/ahmadawais/cut/main/scripts/get.sh | bash
#
# 1. Downloads the release assets listed in its SHA256SUMS (with the GitHub CLI when it's signed in, so private
#    repos work for people with access; else with curl).
# 2. Checks the SHA-256 sums and, for public repos with the GitHub CLI, the build provenance: proof the zip was
#    built by this repo's release workflow from the tagged commit (gh attestation verify).
# 3. Signs the app on this Mac. Apps that need a permission get a local certificate (created once with
#    make-cert.sh) so macOS keeps the grant across updates; LOCAL_ADHOC=1 signs ad-hoc instead.
# 4. Replaces the app in /Applications and opens it. Run again to update.
#
# VERSION=v1.0.0 pins a release (default: latest).
set -euo pipefail

APP="Cut"
REPO="ahmadawais/cut"
BUNDLE="com.ahmadawais.cut"
TCC="Accessibility"              # permissions to reset if the signature changes; empty: needs none
CERT="Cut Local Signing"        # empty: ad-hoc is enough (no permission to keep)

TAG="${VERSION:-latest}"
say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || die "$APP is a macOS app."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

GH=0
command -v gh > /dev/null && gh auth status > /dev/null 2>&1 && GH=1
fetch() {   # fetch <asset>
  if [ "$GH" = 1 ]; then
    if [ "$TAG" = latest ]; then gh release download -R "$REPO" -p "$1" --clobber
    else gh release download "$TAG" -R "$REPO" -p "$1" --clobber; fi
  else
    local base="https://github.com/$REPO/releases/latest/download"
    [ "$TAG" = latest ] || base="https://github.com/$REPO/releases/download/$TAG"
    curl -fsSL --proto '=https' --tlsv1.2 -o "$1" "$base/$1"
  fi
}

say "Downloading $APP ($TAG)"
fetch SHA256SUMS 2> /dev/null || die "no release found for $REPO. Private repo? Sign in with: gh auth login"
FILES=$(awk '{print $2}' SHA256SUMS)
for f in $FILES; do fetch "$f" || die "couldn't download $f"; done

say "Verifying"
shasum -a 256 -c SHA256SUMS || die "checksum mismatch: the download is damaged or was changed"
PRIVATE=$( [ "$GH" = 1 ] && gh repo view "$REPO" --json isPrivate -q .isPrivate 2> /dev/null || echo unknown)
if [ "$GH" = 1 ] && [ "$PRIVATE" = false ]; then
  for f in $FILES; do gh attestation verify "$f" --repo "$REPO" > /dev/null || die "$f has no valid build provenance"; done
  echo "Build provenance: built by $REPO's release workflow"
elif [ "$PRIVATE" = true ]; then
  echo "Build provenance: n/a for private repos (downloaded from $REPO over your signed-in GitHub CLI)"
else
  echo "Build provenance: skipped (install the GitHub CLI and sign in to check it)"
fi

ditto -x -k "$APP.zip" .
[ -d "$APP.app" ] || die "$APP.zip has no $APP.app"
xattr -cr "$APP.app"

ID="-"
if [ -n "$CERT" ] && [ "${LOCAL_ADHOC:-}" != 1 ]; then
  for id in "$CERT" "AA Local Code Signing"; do
    if security find-certificate -c "$id" > /dev/null 2>&1; then ID="$id"; break; fi
  done
  if [ "$ID" = "-" ] && [ -f make-cert.sh ]; then
    say "Creating a local signing certificate (once per Mac)"
    if [ -r /dev/tty ]; then bash make-cert.sh < /dev/tty || true; else bash make-cert.sh || true; fi
    security find-certificate -c "$CERT" > /dev/null 2>&1 && ID="$CERT"
  fi
fi

say "Signing $( [ "$ID" = - ] && echo ad-hoc || echo "with $ID")"
codesign --force --options runtime --timestamp=none --preserve-metadata=entitlements --sign "$ID" "$APP.app"
codesign --verify --strict "$APP.app"

# macOS ties permissions to the signature. If it changed, the switch in System Settings stays on but no longer
# applies; reset it so macOS asks again instead.
dr() { codesign -d -r- "$1" 2> /dev/null | sed -n 's/^designated => //p'; }
RESET=0
if [ -n "$TCC" ] && [ -d "/Applications/$APP.app" ] && [ "$(dr "/Applications/$APP.app")" != "$(dr "$APP.app")" ]; then RESET=1; fi

say "Installing"
pkill -x "$APP" 2> /dev/null || true
for _ in $(seq 50); do pgrep -xq "$APP" || break; sleep 0.1; done
if [ "$RESET" = 1 ]; then for s in $TCC; do tccutil reset "$s" "$BUNDLE" > /dev/null 2>&1 || true; done; fi
rm -rf "/Applications/$APP.app"
ditto "$APP.app" "/Applications/$APP.app"
open "/Applications/$APP.app"

V="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "/Applications/$APP.app/Contents/Info.plist")"
say "$APP $V is in /Applications."
if [ -n "$TCC" ]; then
  [ "$RESET" = 1 ] && echo "Signature changed, so macOS will ask for the permission again."
  echo "First time: System Settings → Privacy & Security → Accessibility → turn on $APP."
  [ "$ID" = - ] && echo "Signed ad-hoc: after each update, turn $APP off and on again there."
fi
exit 0
