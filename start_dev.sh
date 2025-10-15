#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$ROOT_DIR/server"
API_FILE="$ROOT_DIR/lib/constants/api_endpoints.dart"
SERVER_PORT=5000

launch_backend() {
  local backend_cmd="cd \"$BACKEND_DIR\" && npm install && npm start"

  echo "Starting backend server in a new terminal..."
  if command -v osascript >/dev/null 2>&1; then
    local escaped_cmd
    escaped_cmd=$(printf '%s' "$backend_cmd" | sed 's/"/\\"/g')
    osascript <<EOF
tell application "Terminal"
  do script "$escaped_cmd"
end tell
EOF
  elif command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal -- bash -lc "$backend_cmd"
  elif command -v x-terminal-emulator >/dev/null 2>&1; then
    x-terminal-emulator -e bash -lc "$backend_cmd"
  else
    echo "Warning: could not open a new terminal window. Running backend in the background." >&2
    (cd "$BACKEND_DIR" && npm install && npm start) &
  fi
}

find_local_ipv4() {
  local candidate=""

  if command -v ip >/dev/null 2>&1; then
    candidate=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}')
  fi

  if [[ -z "$candidate" ]]; then
    candidate=$(hostname -I 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {print $i; exit}}')
  fi

  if [[ -z "$candidate" && $(uname -s 2>/dev/null) == "Darwin" ]]; then
    candidate=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
  fi

  if [[ -z "$candidate" ]]; then
    echo "Error: Unable to detect local IPv4 address." >&2
    exit 1
  fi

  echo "$candidate"
}

update_api_base_url() {
  local ip_addr="$1"
  local base_url="http://$ip_addr:$SERVER_PORT/api"

  if [[ ! -f "$API_FILE" ]]; then
    echo "Error: API endpoints file not found at $API_FILE" >&2
    exit 1
  fi

  echo "Updating API_BASE_URL to $base_url"
  if [[ $(uname -s) == "Darwin" ]]; then
    sed -i '' -E "s|^const String API_BASE_URL = '.*';|const String API_BASE_URL = '$base_url';|" "$API_FILE"
  else
    sed -i -E "s|^const String API_BASE_URL = '.*';|const String API_BASE_URL = '$base_url';|" "$API_FILE"
  fi
}

main() {
  launch_backend

  local ip_addr
  ip_addr=$(find_local_ipv4)

  update_api_base_url "$ip_addr"

  echo "Running Flutter setup..."
  cd "$ROOT_DIR"
  flutter pub get
  flutter run
}

main "$@"
