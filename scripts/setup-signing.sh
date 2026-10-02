#!/usr/bin/env bash
# One-time setup: create a self-signed "TypoFixrDev" code-signing certificate.
# This keeps the signing identity stable across rebuilds so macOS TCC remembers
# accessibility permissions (ad-hoc signing resets them every deploy).
set -euo pipefail

CERT_NAME="TypoFixrDev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Check if certificate already exists
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
  echo "Certificate '$CERT_NAME' already exists. Nothing to do."
  exit 0
fi

SIGNING_TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$SIGNING_TEMP_DIR"' EXIT

cat > "$SIGNING_TEMP_DIR/cert.conf" <<'EOF'
[ req ]
default_bits       = 2048
distinguished_name = dn
x509_extensions    = codesign
prompt             = no
[ dn ]
CN = TypoFixrDev
[ codesign ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

echo "Creating self-signed code-signing certificate '$CERT_NAME'..."
openssl req -x509 -newkey rsa:2048 \
  -keyout "$SIGNING_TEMP_DIR/key.pem" \
  -out "$SIGNING_TEMP_DIR/cert.pem" \
  -days 3650 -nodes \
  -config "$SIGNING_TEMP_DIR/cert.conf" 2>/dev/null

openssl pkcs12 -export \
  -legacy \
  -out "$SIGNING_TEMP_DIR/cert.p12" \
  -inkey "$SIGNING_TEMP_DIR/key.pem" \
  -in "$SIGNING_TEMP_DIR/cert.pem" \
  -passout pass:typofixr-tmp

security import "$SIGNING_TEMP_DIR/cert.p12" \
  -k "$KEYCHAIN" \
  -T /usr/bin/codesign \
  -P "typofixr-tmp"

echo "Trusting certificate for code signing..."
security find-certificate -c "$CERT_NAME" -p "$KEYCHAIN" > "$SIGNING_TEMP_DIR/exported.pem"
security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$SIGNING_TEMP_DIR/exported.pem"

echo ""
echo "Done! Certificate '$CERT_NAME' installed and trusted in login keychain."
echo "Verify with: security find-identity -v -p codesigning"
