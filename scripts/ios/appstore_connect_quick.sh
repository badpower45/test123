#!/usr/bin/env bash
set -euo pipefail

# Required env vars:
# ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_FILEPATH
# Optional env vars:
# APP_IDENTIFIER, APP_NAME, APP_SKU, APP_PRIMARY_LANGUAGE, IPA_PATH

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"

if [[ -d "/opt/homebrew/opt/ruby/bin" ]]; then
  export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
fi

export SKIP_CREATE_APP="${SKIP_CREATE_APP:-1}"

if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_FILEPATH:-}" ]]; then
  echo "Missing required App Store Connect API key variables."
  echo "Please set: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_FILEPATH"
  exit 1
fi

cd "$IOS_DIR"

if ! command -v bundle >/dev/null 2>&1; then
  echo "Bundler not found. Install Ruby/Bundler first."
  exit 1
fi

bundle check >/dev/null 2>&1 || bundle install

if [[ -n "${IPA_PATH:-}" ]]; then
  echo "Using existing IPA: $IPA_PATH"
  bundle exec fastlane ios create_appstore_app
  bundle exec fastlane ios upload_ipa_to_testflight
else
  echo "Building and uploading a new IPA..."
  bundle exec fastlane ios create_build_upload
fi

echo "Done: App Store Connect/TestFlight flow finished."
