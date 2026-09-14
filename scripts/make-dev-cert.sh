#!/bin/zsh
# Creates a self-signed code signing certificate named "ClipKeeper Development"
# in the login keychain. Builds signed with it keep a stable identity, so the
# Accessibility permission survives rebuilds. Run once.
set -euo pipefail

NAME="ClipKeeper Development"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$NAME"; then
  echo "Identity \"$NAME\" already exists."
  exit 0
fi

TMP="$(mktemp -d)"
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
CNF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" >/dev/null 2>&1
# macOS `security import` needs the legacy PKCS#12 algorithms.
if ! openssl pkcs12 -export -legacy -out "$TMP/dev.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:clipkeeper 2>/dev/null; then
  openssl pkcs12 -export -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
    -out "$TMP/dev.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:clipkeeper
fi

security import "$TMP/dev.p12" -k "$KEYCHAIN" -P clipkeeper -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# Trust the certificate for code signing in the user's trust settings.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" || echo "Trust setting not added (you can allow it in Keychain Access)."
rm -rf "$TMP"

security find-identity -v -p codesigning "$KEYCHAIN" | grep "$NAME" || { echo "Identity was not created." >&2; exit 1; }
echo "Created identity \"$NAME\"."
