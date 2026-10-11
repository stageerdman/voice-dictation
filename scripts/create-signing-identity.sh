#!/bin/bash
# One-time: create a stable self-signed code-signing identity in the login
# keychain. Signing the dev app with a STABLE identity (instead of ad-hoc) means
# macOS TCC grants (Accessibility, Input Monitoring, Microphone) survive rebuilds
# — you grant permission once, not every time you rebuild.
set -euo pipefail

IDENTITY="Voice Dictation Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Signing identity '$IDENTITY' already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

# Self-signed key + cert with the codeSigning usage codesign requires.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf"
# -legacy + a non-empty password: Apple's `security` can't verify the PKCS12
# MAC that modern OpenSSL 3 writes with an empty password.
P12PASS="voicedictation"
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/identity.p12" -passout "pass:$P12PASS" -name "$IDENTITY"

# Import; pre-authorize codesign to use the key without a GUI prompt.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12PASS" -T /usr/bin/codesign

echo
echo "Created signing identity '$IDENTITY'."
echo "If macOS later pops a keychain prompt while signing, click 'Always Allow'."
