#!/bin/bash
# Optional, free, one time per Mac: creates a self-signed code-signing certificate "Cut Local Signing" in your
# login keychain. scripts/build.sh then signs with it, so the signature is the same on every rebuild and macOS
# keeps Cut's Accessibility permission. Without it Cut is signed ad-hoc and works the same, but you re-allow
# Accessibility after each rebuild. No Apple Developer account ($99) involved.
#
# The private key is created here and never leaves your login keychain; only /usr/bin/codesign may use it.
# macOS asks for your login password once (here, or a "codesign wants to access key" dialog → Always Allow).
# Exit 0: created. Exit 10: already there.
set -euo pipefail
NAME="Cut Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" > /dev/null 2>&1; then echo "Already there: $NAME"; exit 10; fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
umask 077
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CFG
/usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -days 7300 -sha256 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cfg" 2> /dev/null
PASS="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/id.p12" -passout "pass:$PASS" 2> /dev/null
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign > /dev/null
echo "Created code-signing identity: $NAME"
if [ -t 0 ]; then
    echo "Enter your Mac login password once so codesign can sign without asking:"
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$NAME" "$KEYCHAIN" > /dev/null \
        || echo "Skipped: on the first build, enter the password in the dialog and click Always Allow."
fi
