#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_ENV_FILE="$SCRIPT_DIR/.env.runtime"
OPAM_SWITCH="${OPAM_SWITCH:-4.14.0}"

load_project_env() {
  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
  fi

  if [[ -f "$RUNTIME_ENV_FILE" ]]; then
    set -a
    source "$RUNTIME_ENV_FILE"
    set +a
  fi
}

load_opam_env() {
  if command -v opam &>/dev/null; then
    eval "$(opam env --switch="$OPAM_SWITCH")"
    hash -r
  fi
}

require_command() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "$cmd" &>/dev/null; then
    echo "Missing required command: $cmd" >&2
    if [[ -n "$hint" ]]; then
      echo "$hint" >&2
    fi
    exit 1
  fi
}

require_runtime_env() {
  if [[ ! -f "$RUNTIME_ENV_FILE" ]]; then
    echo "Missing .env.runtime. Run ./bootstrap.sh first." >&2
    exit 1
  fi
}

detect_chrome_bin() {
  if [[ -n "${OVERLAY_BROWSER_PATH:-}" ]]; then
    printf '%s\n' "$OVERLAY_BROWSER_PATH"
    return 0
  fi

  local candidate
  for candidate in \
    /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
    /Applications/Brave\ Browser.app/Contents/MacOS/Brave\ Browser \
    "$(command -v google-chrome 2>/dev/null || true)" \
    "$(command -v chromium 2>/dev/null || true)" \
    "$(command -v chromium-browser 2>/dev/null || true)"
  do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_node_modules() {
  local controller_dir="$SCRIPT_DIR/src/controller"
  local missing=0
  local required_modules=(
    "puppeteer-core"
    "mailparser"
    "imapflow"
    "sqlite"
    "sqlite3"
  )

  for module in "${required_modules[@]}"; do
    if [[ ! -d "$controller_dir/node_modules/$module" ]]; then
      missing=1
      break
    fi
  done

  if [[ "$missing" -eq 1 ]]; then
    if ! command -v npm &>/dev/null; then
      echo "ERROR: npm not found. Install Node.js 18+ (npm is bundled with it)." >&2
      echo "Use nvm (https://github.com/nvm-sh/nvm) or your system package manager." >&2
      exit 1
    fi
    echo "Installing Node dependencies..."
    (cd "$controller_dir" && npm install)
  fi
}

# -----------------------------------------------------------------
# ensure_tmpfs: mount /tmp/umvc3247 as tmpfs if not already mounted
#   - size can be overridden with TMPFS_SIZE env var (default 500M)
#   - mode=1777 matches typical /tmp permissions
# -----------------------------------------------------------------
ensure_tmpfs() {
  local mountpoint="/tmp/umvc3247"
  local size="${TMPFS_SIZE:-500M}"
  # If already mounted, nothing to do (portable check)
  if mount | grep -q "on $mountpoint "; then
    return 0
  fi
  mkdir -p "$mountpoint"
  # Try to mount a tmpfs; on systems where this is unsupported we fall back to a regular directory.
  if ! mount -t tmpfs -o size=$size,mode=1777 tmpfs "$mountpoint" 2>/dev/null; then
    echo "[controller] tmpfs mount not supported – using regular directory $mountpoint"
  fi
}

stop_pid_file() {
  local pid_file="$1"
  local label="$2"

  [[ -f "$pid_file" ]] || return 0

  local pid
  pid="$(cat "$pid_file")"

  if kill -0 "$pid" 2>/dev/null; then
    echo "Stopping $label (PID $pid)..."
    kill "$pid"

    for _ in {1..20}; do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done

    if kill -0 "$pid" 2>/dev/null; then
      echo "Force stopping $label (PID $pid)..."
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi

  rm -f "$pid_file"
}
