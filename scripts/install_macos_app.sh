#!/usr/bin/env bash
set -euo pipefail

APP_INSTALL_NAME="${APP_INSTALL_NAME:-Desktop Pet.app}"
DEFAULT_DESTINATION="/Applications"
REPO_URL="${DESKTOP_PET_REPO_URL:-https://github.com/He2y/desktop_pet.git}"
RELEASE_URL="${DESKTOP_PET_RELEASE_URL:-https://github.com/He2y/desktop_pet/releases/latest/download/DesktopPet.zip}"
OPEN_AFTER_INSTALL="${OPEN_AFTER_INSTALL:-0}"
INSTALL_FROM_SOURCE="${INSTALL_FROM_SOURCE:-}"

TEMP_ROOT=""
ROOT_DIR=""
APP_PATH=""

usage() {
  cat <<'USAGE'
Install Desktop Pet for macOS.

Usage:
  scripts/install_macos_app.sh [destination]

Default behavior:
  - curl | bash remote install downloads the latest prebuilt release package.
  - local repository install builds from source, so local changes are included.

Environment:
  INSTALL_DESTINATION    Install directory or full .app path. Defaults to /Applications.
  OPEN_AFTER_INSTALL     Set to 1 to launch the app after installation.
  APP_INSTALL_NAME       Installed app bundle name. Defaults to "Desktop Pet.app".
  DESKTOP_PET_RELEASE_URL Prebuilt zip URL. Defaults to the latest GitHub Release.
  DESKTOP_PET_REPO_URL   Repository used only for source-build fallback.
  INSTALL_FROM_SOURCE    Set to 1 to force a source build, or 0 to force release download.

Examples:
  scripts/install_macos_app.sh
  INSTALL_DESTINATION="$HOME/Applications" scripts/install_macos_app.sh
  OPEN_AFTER_INSTALL=1 scripts/install_macos_app.sh
  INSTALL_FROM_SOURCE=1 scripts/install_macos_app.sh
USAGE
}

log() {
  printf '[Desktop Pet] %s\n' "$1"
}

fail() {
  printf '[Desktop Pet] Error: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [[ -n "${TEMP_ROOT:-}" ]]; then
    rm -rf "$TEMP_ROOT"
  fi
}

trap cleanup EXIT

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "this installer only supports macOS."
fi

SCRIPT_PATH="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  CANDIDATE_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
  if [[ -f "$CANDIDATE_ROOT/Package.swift" && -x "$CANDIDATE_ROOT/scripts/build_macos_app.sh" ]]; then
    ROOT_DIR="$CANDIDATE_ROOT"
  fi
fi

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

prepare_destination() {
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
}

developer_tools_available() {
  /usr/bin/xcode-select -p >/dev/null 2>&1
}

require_developer_tools() {
  if ! developer_tools_available; then
    fail "Xcode Command Line Tools are required for source builds. Install them with: xcode-select --install"
  fi

  /usr/bin/xcrun -find swift >/dev/null 2>&1 || fail "Swift was not found in the active developer tools."
  /usr/bin/xcrun -find git >/dev/null 2>&1 || fail "Git was not found in the active developer tools."
}

download_prebuilt_app() {
  command -v curl >/dev/null 2>&1 || fail "curl is required to download the prebuilt app."
  command -v ditto >/dev/null 2>&1 || fail "ditto is required to extract the prebuilt app."

  TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/desktop-pet-install.XXXXXX")"
  local zip_path="$TEMP_ROOT/DesktopPet.zip"
  local extract_dir="$TEMP_ROOT/prebuilt"

  log "Downloading prebuilt app from GitHub Releases"
  if ! curl --fail --location --retry 3 --retry-delay 2 --retry-connrefused --output "$zip_path" "$RELEASE_URL"; then
    fail "could not download the prebuilt app. Check network access to GitHub Releases or install from a cloned repository with Xcode Command Line Tools."
  fi

  mkdir -p "$extract_dir"
  if ! ditto -x -k "$zip_path" "$extract_dir"; then
    fail "could not extract the prebuilt app zip."
  fi

  APP_PATH="$(find "$extract_dir" -maxdepth 3 -name '*.app' -type d -print | head -n 1)"
  [[ -d "$APP_PATH/Contents" ]] || fail "the prebuilt zip did not contain a valid app bundle."
}

build_source_app() {
  require_developer_tools

  if [[ -z "$ROOT_DIR" ]]; then
    TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/desktop-pet-install.XXXXXX")"
    log "Cloning latest source from $REPO_URL"
    "$(/usr/bin/xcrun -find git)" clone --depth 1 "$REPO_URL" "$TEMP_ROOT/desktop_pet" >/dev/null
    ROOT_DIR="$TEMP_ROOT/desktop_pet"
  fi

  local build_script="$ROOT_DIR/scripts/build_macos_app.sh"
  [[ -x "$build_script" ]] || fail "build script is not executable: $build_script"

  log "Building release app from source"
  export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
  local build_output
  build_output="$("$build_script")"
  printf '%s\n' "$build_output"
  APP_PATH="$(printf '%s\n' "$build_output" | tail -n 1)"

  [[ -d "$APP_PATH/Contents" ]] || fail "build did not produce a valid app bundle: $APP_PATH"
}

install_app() {
  [[ "$INSTALL_PATH" == *.app ]] || fail "install path must end with .app: $INSTALL_PATH"
  [[ -d "$APP_PATH/Contents" ]] || fail "cannot install invalid app bundle: $APP_PATH"

  log "Installing to $INSTALL_PATH"
  if [[ -e "$INSTALL_PATH" ]]; then
    rm -rf "$INSTALL_PATH"
  fi

  ditto "$APP_PATH" "$INSTALL_PATH"

  if command -v xattr >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "$INSTALL_PATH" 2>/dev/null || true
  fi

  touch "$INSTALL_PATH"

  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -x "$lsregister" ]]; then
    "$lsregister" -f "$INSTALL_PATH" >/dev/null 2>&1 || true
  fi

  if command -v codesign >/dev/null 2>&1; then
    codesign --verify --deep --strict "$INSTALL_PATH" >/dev/null
  fi

  log "Installed successfully: $INSTALL_PATH"

  if [[ "$OPEN_AFTER_INSTALL" == "1" ]]; then
    log "Opening Desktop Pet"
    open "$INSTALL_PATH"
  fi
}

prepare_destination

if [[ "$INSTALL_FROM_SOURCE" == "1" ]]; then
  build_source_app
elif [[ "$INSTALL_FROM_SOURCE" == "0" ]]; then
  download_prebuilt_app
elif [[ -n "$ROOT_DIR" ]]; then
  build_source_app
else
  download_prebuilt_app
fi

install_app
