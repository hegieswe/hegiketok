#!/usr/bin/env bash
# Rilis macOS HegiKetok: uji → build release → tanda tangan → kemas (.dmg + .zip)
# → checksum. Bawaan: tanda tangan AD-HOC (gratis, untuk pemakaian sendiri/tim).
#
#   ./scripts/release_macos.sh                 # ad-hoc, dengan analyze + test
#   SKIP_CHECKS=1 ./scripts/release_macos.sh   # lewati analyze + test
#
# Nanti bila punya Apple Developer ID (distribusi publik tanpa peringatan):
#   SIGN_IDENTITY="Developer ID Application: NAMA (TEAMID)" \
#   NOTARY_PROFILE="hegiketok-notary" ./scripts/release_macos.sh
# (NOTARY_PROFILE = profil `xcrun notarytool store-credentials`; kredensial
#  Apple tetap di Keychain-mu, tidak pernah ditulis di skrip ini.)
#
# Hasil di dist/:
#   HegiKetok-<versi>-macos.dmg   ← diunggah ke GitHub Release (dipakai updater)
#   HegiKetok-<versi>-macos.zip
#   SHA256SUMS.txt
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="HegiKetok"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
ENTITLEMENTS="macos/Runner/Release.entitlements"
APP="build/macos/Build/Products/Release/${APP_NAME}.app"
DIST="dist"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31mGAGAL: %s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "skrip ini hanya untuk macOS."
for tool in flutter codesign hdiutil ditto shasum; do
  command -v "$tool" >/dev/null 2>&1 || die "'$tool' tidak ditemukan di PATH."
done
[[ -f "$ENTITLEMENTS" ]] || die "entitlements tidak ada: $ENTITLEMENTS"

# ── Versi: satu sumber kebenaran = pubspec.yaml ────────────────────────────
VERSION="$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' pubspec.yaml | head -1)"
[[ -n "$VERSION" ]] || die "tidak bisa membaca 'version:' dari pubspec.yaml"
CONST_VERSION="$(sed -nE "s/^const String kAppVersion = '([^']+)';.*/\1/p" \
  lib/src/features/updates/update_checker.dart | head -1)"
[[ "$CONST_VERSION" == "$VERSION" ]] || die \
  "kAppVersion ($CONST_VERSION) ≠ pubspec ($VERSION). Samakan dulu — kalau tidak, cek pembaruan akan keliru."

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  MODE="ad-hoc"
else
  MODE="Developer ID"
fi
say "HegiKetok $VERSION — tanda tangan: $MODE"

# ── Uji ────────────────────────────────────────────────────────────────────
say "flutter pub get"
flutter pub get

if [[ "${SKIP_CHECKS:-0}" != "1" ]]; then
  say "flutter analyze"
  flutter analyze
  say "flutter test"
  flutter test
else
  say "analyze + test DILEWATI (SKIP_CHECKS=1)"
fi

# ── Build ──────────────────────────────────────────────────────────────────
say "flutter build macos --release"
flutter build macos --release
[[ -d "$APP" ]] || die "hasil build tidak ditemukan: $APP"

# ── Tanda tangan (dari dalam ke luar: framework/dylib dulu, lalu .app) ─────
say "codesign ($MODE)"
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$MODE" == "Developer ID" ]]; then
  # Hardened runtime + timestamp wajib untuk notarisasi.
  SIGN_ARGS+=(--options runtime --timestamp)
fi

if [[ -d "$APP/Contents/Frameworks" ]]; then
  # Urutan terdalam dulu supaya segel luar tidak rusak oleh perubahan di dalam.
  while IFS= read -r item; do
    codesign "${SIGN_ARGS[@]}" "$item"
  done < <(find "$APP/Contents/Frameworks" -depth \
            \( -name '*.dylib' -o -name '*.framework' \) -print)
fi
codesign "${SIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP"

say "verifikasi tanda tangan"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E 'Identifier|Signature|TeamIdentifier|flags' || true

# ── Kemas ──────────────────────────────────────────────────────────────────
rm -rf "$DIST"
mkdir -p "$DIST"
BASE="${APP_NAME}-${VERSION}-macos"
ZIP="$DIST/$BASE.zip"
DMG="$DIST/$BASE.dmg"

say "zip → $ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

say "dmg → $DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov -quiet "$DMG"
if [[ "$MODE" == "Developer ID" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

# ── Notarisasi (hanya Developer ID + profil tersedia) ──────────────────────
if [[ "$MODE" == "Developer ID" && -n "$NOTARY_PROFILE" ]]; then
  say "notarisasi (menunggu Apple…)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
elif [[ "$MODE" == "Developer ID" ]]; then
  echo "    (NOTARY_PROFILE kosong → notarisasi dilewati)"
fi

# ── Checksum ───────────────────────────────────────────────────────────────
say "checksum"
( cd "$DIST" && shasum -a 256 "$BASE.dmg" "$BASE.zip" | tee SHA256SUMS.txt )

say "Selesai → $DIST/"
ls -lh "$DIST"
if [[ "$MODE" == "ad-hoc" ]]; then
  cat <<'EOF'

Catatan tanda tangan ad-hoc:
  • Di Mac sendiri: seret ke Applications lalu buka seperti biasa.
  • Di Mac lain, bila berkas datang lewat browser/AirDrop, macOS memblokir saat
    pertama dibuka. Izinkan sekali lewat System Settings → Privacy & Security →
    "Open Anyway", atau:
        xattr -dr com.apple.quarantine /Applications/HegiKetok.app
  • Selengkapnya: DISTRIBUTION.md
EOF
fi
