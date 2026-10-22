#!/bin/bash
# Creates a self-signed code-signing certificate "Tidemark Local Signing" in the login keychain,
# so local builds keep one signing identity. Run once, by hand: it changes your real Keychain.
# Then: TIDEMARK_SIGN_IDENTITY="Tidemark Local Signing" ./build.sh
set -euo pipefail
NAME="Tidemark Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists in the login keychain."; exit 0
fi

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cat > "$work/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF
pass="$(openssl rand -hex 12)"
SSL=/usr/bin/openssl   # the system LibreSSL: a Homebrew OpenSSL 3 writes a .p12 that `security import` rejects
"$SSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/cert.conf" \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
"$SSL" pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$NAME" \
  -out "$work/id.p12" -passout "pass:$pass"
security import "$work/id.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign
echo "Created \"$NAME\". macOS may ask you to trust it: open Keychain Access, double-click it,"
echo "and set Code Signing to Always Trust."
