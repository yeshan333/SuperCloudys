#!/bin/bash
# Build, install, and relaunch SuperCloudys locally with a *stable* self-signed
# identity so macOS TCC (Accessibility, etc.) survives rebuilds.
#
# First run: imports a long-lived cert into your login keychain (one prompt),
#            then you grant Accessibility in System Settings ONCE.
# Subsequent runs: no prompts, no TCC re-grant — just rebuild & restart.
set -euo pipefail

CERT_CN="SuperCloudys Local Dev"
CERT_SHA1=""
INSTALL_DIR="$HOME/Applications"
APP_NAME="SuperCloudys.app"
DERIVED="/tmp/supercloudys-build"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
cd "$PROJECT_ROOT"

ensure_cert() {
  local installed="$INSTALL_DIR/$APP_NAME"
  if [ -d "$installed" ]; then
    local cert_dir cert_file
    cert_dir="$(mktemp -d)"
    cert_file="$cert_dir/cert"
    if codesign -d --extract-certificates="$cert_file" "$installed" 2>/dev/null \
         && [ -f "${cert_file}0" ]; then
      CERT_SHA1="$(shasum -a 1 "${cert_file}0" | awk '{print toupper($1)}')"
    fi
    rm -rf "$cert_dir"
    if [ -n "$CERT_SHA1" ] && security find-identity -p codesigning login.keychain-db \
         | grep -F "$CERT_SHA1" >/dev/null; then
      echo "→ Reusing installed signing identity: $CERT_SHA1"
      return 0
    fi
    CERT_SHA1=""
  fi

  CERT_SHA1="$(security find-identity -p codesigning login.keychain-db \
    | awk -v name="\"$CERT_CN\"" 'index($0, name) { print $2; exit }')"
  if [ -n "$CERT_SHA1" ]; then
    echo "→ Reusing signing identity: $CERT_SHA1"
    return 0
  fi
  command -v openssl >/dev/null || {
    echo "✗ openssl is required to create the local signing certificate."
    exit 1
  }
  echo "→ Creating local self-signed cert: $CERT_CN (one-time, 10y)"
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
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
  CERT_SHA1="$(openssl x509 -in "$tmp/cert.pem" -noout -fingerprint -sha1 \
    | cut -d= -f2 | tr -d ':')"
  rm -rf "$tmp"
  trap - EXIT
  echo "✓ Cert installed in login keychain."
}

build_signed() {
  echo "→ Building Release with identity: $CERT_SHA1"
  rm -rf "$DERIVED"
  xcodebuild \
    -project SuperCloudys.xcodeproj \
    -scheme SuperCloudys \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="$CERT_SHA1" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    CLANG_COVERAGE_MAPPING=NO \
    CLANG_ENABLE_CODE_COVERAGE=NO \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    clean build >/tmp/supercloudys-build.log 2>&1 || {
      echo "✗ Build failed. Last 30 lines:"
      tail -30 /tmp/supercloudys-build.log
      exit 1
  }
  local built="$DERIVED/Build/Products/Release/$APP_NAME"
  if size -m "$built/Contents/MacOS/SuperCloudys" | grep -F __LLVM_COV >/dev/null; then
    echo "✗ Release binary unexpectedly contains code coverage instrumentation."
    exit 1
  fi
  if codesign -d --entitlements :- "$built" 2>/dev/null | grep -F get-task-allow >/dev/null; then
    echo "✗ Release app unexpectedly allows debugger attachment."
    exit 1
  fi
  echo "✓ Build succeeded."
}

stop_running() {
  osascript -e "quit app \"SuperCloudys\"" 2>/dev/null || true
  sleep 1
  pkill -x SuperCloudys 2>/dev/null || true
  pkill -x SuperCloudysExtension 2>/dev/null || true
  sleep 1
}

install_and_launch() {
  local src="$DERIVED/Build/Products/Release/$APP_NAME"
  local dst="$INSTALL_DIR/$APP_NAME"
  local staged="$INSTALL_DIR/.$APP_NAME.new"
  local backup="$INSTALL_DIR/.$APP_NAME.old"
  mkdir -p "$INSTALL_DIR"
  rm -rf "$staged" "$backup"
  ditto "$src" "$staged"
  codesign --verify --deep --strict --verbose=2 "$staged"
  if [ -e "$dst" ]; then mv "$dst" "$backup"; fi
  if ! mv "$staged" "$dst"; then
    [ ! -e "$backup" ] || mv "$backup" "$dst"
    echo "✗ Install failed; restored the previous app."
    exit 1
  fi
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$dst"
  open "$dst"
  sleep 1
  if pgrep -xf "$dst/Contents/MacOS/SuperCloudys" >/dev/null; then
    rm -rf "$backup"
    killall Finder 2>/dev/null || true
    echo "✓ SuperCloudys is running from $dst"
  else
    rm -rf "$dst"
    if [ -e "$backup" ]; then
      mv "$backup" "$dst"
      open "$dst"
    fi
    echo "✗ SuperCloudys did not start; restored the previous app."
    exit 1
  fi
}

ensure_cert
build_signed
stop_running
install_and_launch

echo ""
echo "✓ Done. Identity '$CERT_SHA1' is stable — TCC permissions persist."
echo "  If this is the first install, grant Accessibility once at:"
echo "  System Settings → Privacy & Security → Accessibility → add $INSTALL_DIR/$APP_NAME"
