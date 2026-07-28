#!/bin/bash
# =============================================================================
# Oldies Workers App — Build & Upload to App Store Connect
# =============================================================================

set -e

# ── ألوان الـ Terminal ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_step() { echo -e "\n${BLUE}${BOLD}▶ $1${NC}"; }
log_ok()   { echo -e "${GREEN}✓ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
log_err()  { echo -e "${RED}✗ خطأ: $1${NC}"; exit 1; }

# ── المتغيرات ────────────────────────────────────────────────────────────────
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$PROJECT_ROOT/ios"

KEY_ID="SYG3T4BA82"
ISSUER_ID="07d5791f-a9e4-467c-8c35-d0d55f906b55"
AUTH_KEY_PATH="$PROJECT_ROOT/AuthKey_SYG3T4BA82.p8"
EXPORT_OPTIONS="$IOS_DIR/ExportOptions/AppStore.plist"
IPA_DIR="$PROJECT_ROOT/build/ios/ipa"

# ── التحقق من المتطلبات ─────────────────────────────────────────────────────
log_step "التحقق من المتطلبات..."
command -v flutter    >/dev/null 2>&1 || log_err "Flutter غير موجود في PATH"
command -v xcodebuild >/dev/null 2>&1 || log_err "Xcode غير مثبت"
[ -f "$AUTH_KEY_PATH" ]   || log_err "ملف AuthKey غير موجود:\n  $AUTH_KEY_PATH"
[ -f "$EXPORT_OPTIONS" ]  || log_err "ملف ExportOptions غير موجود:\n  $EXPORT_OPTIONS"
log_ok "جميع المتطلبات متوفرة"

# ── معلومات البيلد ──────────────────────────────────────────────────────────
VERSION=$(grep '^version:' "$PROJECT_ROOT/pubspec.yaml" | awk '{print $2}')
BUILD_NAME=$(echo "$VERSION" | cut -d'+' -f1)
BUILD_NUMBER=$(echo "$VERSION" | cut -d'+' -f2)

echo -e "\n${CYAN}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${CYAN}    Oldies Workers — App Store Build      ${NC}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════${NC}"
echo -e "  Version      : ${BOLD}$BUILD_NAME${NC}"
echo -e "  Build Number : ${BOLD}$BUILD_NUMBER${NC}"
echo -e "  Key ID       : ${BOLD}$KEY_ID${NC}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════${NC}\n"

# read -p "$(echo -e ${YELLOW}هل تريد المتابعة؟ [y/N]: ${NC})" -n 1 CONFIRM
# echo
# [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "تم الإلغاء."; exit 0; }

# ── Step 1: تنظيف ───────────────────────────────────────────────────────────
log_step "Step 1/5 — تنظيف البيلد السابق..."
cd "$PROJECT_ROOT"
flutter clean
log_ok "تم التنظيف"

# ── Step 2: تحميل الـ Packages ──────────────────────────────────────────────
log_step "Step 2/5 — تحميل الـ Packages..."
flutter pub get
log_ok "تم تحميل الـ Packages"

# ── Step 3: تثبيت CocoaPods ─────────────────────────────────────────────────
log_step "Step 3/5 — تثبيت CocoaPods..."
cd "$IOS_DIR"
pod install --repo-update
cd "$PROJECT_ROOT"
log_ok "تم تثبيت CocoaPods"

# ── Step 4: بناء الـ IPA ─────────────────────────────────────────────────────
log_step "Step 4/5 — بناء IPA (Release)..."
# flutter build ipa يقوم بـ Archive + Export تلقائياً
flutter build ipa \
  --release \
  --export-options-plist="$EXPORT_OPTIONS" \
  --no-pub

# البحث عن ملف الـ IPA
IPA_FILE=$(find "$IPA_DIR" -name "*.ipa" 2>/dev/null | head -1)

# احتياطياً: flutter قد يضع الـ IPA في مسار مختلف
if [ -z "$IPA_FILE" ]; then
  IPA_FILE=$(find "$PROJECT_ROOT/build" -name "*.ipa" 2>/dev/null | head -1)
fi

[ -n "$IPA_FILE" ] || log_err "لم يُنشأ ملف IPA. راجع الأخطاء أعلاه."
log_ok "تم إنشاء IPA: $IPA_FILE"

# ── Step 5: رفع الـ IPA ──────────────────────────────────────────────────────
log_step "Step 5/5 — رفع الـ IPA على App Store Connect..."

# نستخدم xcrun altool (متاح في Xcode Command Line Tools)
xcrun altool \
  --upload-app \
  --type ios \
  --file "$IPA_FILE" \
  --apiKey "$KEY_ID" \
  --apiIssuer "$ISSUER_ID" \
  --verbose

log_ok "تم الرفع بنجاح على App Store Connect!"

# ── ملخص ──────────────────────────────────────────────────────────────────
echo -e "\n${GREEN}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✓ اكتمل البيلد والرفع بنجاح!          ${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
echo -e "  IPA : ${BOLD}$IPA_FILE${NC}"
echo -e "\n  تحقق من البيلد على:"
echo -e "  ${CYAN}https://appstoreconnect.apple.com${NC}\n"
