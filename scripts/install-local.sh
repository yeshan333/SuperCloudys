#!/bin/bash
# Build, install, and relaunch RMenu locally with a *stable* self-signed
# identity so macOS TCC (Accessibility, etc.) survives rebuilds.
#
# First run: imports a long-lived cert into your login keychain (one prompt),
#            then you grant Accessibility in System Settings ONCE.
# Subsequent runs: no prompts, no TCC re-grant — just rebuild & restart.
set -euo pipefail

CERT_CN="RMenu Local Dev"
INSTALL_DIR="$HOME/Applications"
APP_NAME="RMenu.app"
DERIVED="/tmp/rmenu-build"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

ensure_cert() {
  if security find-identity -v -p codesigning login.keychain-db \
       | grep -q "\"$CERT_CN\""; then
    return 0
  fi
  echo "→ Creating local self-signed cert: $CERT_CN (one-time, 10y)"
  local tmp; tmp="$(mktemp -d)"
  trap "rm -rf $tmp" RETURN
  cat > "$tmp/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CERT_CN
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:false
CONF
  openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.conf"
  # `-legacy` keeps the older KDF macOS `security` can import.
  openssl pkcs12 -export -legacy -out "$tmp/cert.p12" \
    -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -passout pass:local
  security import "$tmp/cert.p12" -k login.keychain-db -P local \
    -T /usr/bin/codesign -T /usr/bin/security
  echo "✓ Cert installed in login keychain."
}

build_signed() {
  echo "→ Building Release with identity: $CERT_CN"
  rm -rf "$DERIVED"
  xcodebuild \
    -project RMenu.xcodeproj \
    -scheme RMenu \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="$CERT_CN" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    clean build >/tmp/rmenu-build.log 2>&1 || {
      echo "✗ Build failed. Last 30 lines:"
      tail -30 /tmp/rmenu-build.log
      exit 1
    }
  echo "✓ Build succeeded."
}

stop_running() {
  osascript -e "quit app \"RMenu\"" 2>/dev/null || true
  sleep 1
  pkill -x RMenu 2>/dev/null || true
  pkill -f RMenuExtension 2>/dev/null || true
  sleep 1
}

install_and_launch() {
  local src="$DERIVED/Build/Products/Release/$APP_NAME"
  local dst="$INSTALL_DIR/$APP_NAME"
  mkdir -p "$INSTALL_DIR"
  rm -rf "$dst"
  cp -R "$src" "$dst"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$dst"
  open "$dst"
  sleep 1
  if pgrep -xf "$dst/Contents/MacOS/RMenu" >/dev/null; then
    echo "✓ RMenu is running from $dst"
  else
    echo "✗ RMenu did not start. Check Console for errors."
    exit 1
  fi
}

ensure_cert
build_signed
stop_running
install_and_launch

echo ""
echo "✓ Done. Identity '$CERT_CN' is stable — TCC permissions persist."
echo "  If this is the first install, grant Accessibility once at:"
echo "  System Settings → Privacy & Security → Accessibility → add $INSTALL_DIR/$APP_NAME"
