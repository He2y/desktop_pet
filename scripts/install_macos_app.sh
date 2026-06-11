#!/usr/bin/env bash
set -euo pipefail

APP_INSTALL_NAME="${APP_INSTALL_NAME:-Desktop Pet.app}"
DEFAULT_DESTINATION="/Applications"
REPO_URL="${DESKTOP_PET_REPO_URL:-https://github.com/He2y/desktop_pet.git}"
OPEN_AFTER_INSTALL="${OPEN_AFTER_INSTALL:-0}"

usage() {
  cat <<'USAGE'
Install Desktop Pet for macOS.

Usage:
  scripts/install_macos_app.sh [destination]

Environment:
  INSTALL_DESTINATION   Install directory or full .app path. Defaults to /Applications.
  OPEN_AFTER_INSTALL    Set to 1 to launch the app after installation.
  APP_INSTALL_NAME      Installed app bundle name. Defaults to "Desktop Pet.app".
  DESKTOP_PET_REPO_URL  Repository used when the script is run from curl.

Examples:
  scripts/install_macos_app.sh
  INSTALL_DESTINATION="$HOME/Applications" scripts/install_macos_app.sh
  OPEN_AFTER_INSTALL=1 scripts/install_macos_app.sh
USAGE
}

log() {
  printf '[Desktop Pet] %s\n' "$1"
}

fail() {
  printf '[Desktop Pet] Error: %s\n' "$1" >&2
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "this installer only supports macOS."
fi

if ! command -v swift >/dev/null 2>&1; then
  fail "Swift is missing. Install Xcode Command Line Tools first: xcode-select --install"
fi

SCRIPT_PATH="${BASH_SOURCE[0]:-}"
ROOT_DIR=""
TEMP_ROOT=""

if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  CANDIDATE_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
  if [[ -f "$CANDIDATE_ROOT/Package.swift" && -x "$CANDIDATE_ROOT/scripts/build_macos_app.sh" ]]; then
    ROOT_DIR="$CANDIDATE_ROOT"
  fi
fi

if [[ -z "$ROOT_DIR" ]]; then
  if ! command -v git >/dev/null 2>&1; then
    fail "Git is missing and is required for one-line remote installation."
  fi

  TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/desktop-pet-install.XXXXXX")"
  trap '[[ -n "${TEMP_ROOT:-}" ]] && rm -rf "$TEMP_ROOT"' EXIT
  log "Cloning latest source from $REPO_URL"
  git clone --depth 1 "$REPO_URL" "$TEMP_ROOT/desktop_pet" >/dev/null
  ROOT_DIR="$TEMP_ROOT/desktop_pet"
fi

BUILD_SCRIPT="$ROOT_DIR/scripts/build_macos_app.sh"
[[ -x "$BUILD_SCRIPT" ]] || fail "build script is not executable: $BUILD_SCRIPT"

DESTINATION="${1:-${INSTALL_DESTINATION:-$DEFAULT_DESTINATION}}"

if [[ "$DESTINATION" == *.app ]]; then
  INSTALL_PATH="$DESTINATION"
  INSTALL_DIR="$(dirname "$INSTALL_PATH")"
else
  INSTALL_DIR="${DESTINATION%/}"
  INSTALL_PATH="$INSTALL_DIR/$APP_INSTALL_NAME"
fi

prepare_install_dir() {
  local target_dir="$1"
  mkdir -p "$target_dir" 2>/dev/null && [[ -w "$target_dir" ]]
}

if ! prepare_install_dir "$INSTALL_DIR"; then
  if [[ "$DESTINATION" == "$DEFAULT_DESTINATION" ]]; then
    INSTALL_DIR="$HOME/Applications"
    INSTALL_PATH="$INSTALL_DIR/$APP_INSTALL_NAME"
    prepare_install_dir "$INSTALL_DIR" || fail "cannot write to /Applications or $HOME/Applications."
    log "No write permission for /Applications; installing to $INSTALL_DIR instead."
  else
    fail "cannot write to install destination: $INSTALL_DIR"
  fi
fi

log "Building release app"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
BUILD_OUTPUT="$("$BUILD_SCRIPT")"
printf '%s\n' "$BUILD_OUTPUT"
APP_PATH="$(printf '%s\n' "$BUILD_OUTPUT" | tail -n 1)"

[[ -d "$APP_PATH/Contents" ]] || fail "build did not produce a valid app bundle: $APP_PATH"
[[ "$INSTALL_PATH" == *.app ]] || fail "install path must end with .app: $INSTALL_PATH"

log "Installing to $INSTALL_PATH"
if [[ -e "$INSTALL_PATH" ]]; then
  rm -rf "$INSTALL_PATH"
fi

ditto "$APP_PATH" "$INSTALL_PATH"

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$INSTALL_PATH" 2>/dev/null || true
fi

touch "$INSTALL_PATH"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$INSTALL_PATH" >/dev/null 2>&1 || true
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --verify --deep --strict "$INSTALL_PATH" >/dev/null
fi

log "Installed successfully: $INSTALL_PATH"

if [[ "$OPEN_AFTER_INSTALL" == "1" ]]; then
  log "Opening Desktop Pet"
  open "$INSTALL_PATH"
fi
