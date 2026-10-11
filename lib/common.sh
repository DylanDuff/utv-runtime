# Shared config and helpers. Sourced by ./utv-runtime, never run directly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ROOT/.utv-runtime.conf"

PACKAGE="com.google.android.youtube.tv"
# Stock YouTube is a Google-signed system app, so the patched build installs beside it under this
# fixed package. Keeping it fixed means every run updates the same app and keeps its login.
NEW_PACKAGE="com.google.android.youtube.tv.adfree"
DEFAULT_LABEL="YouTube Test"
ADB_PORT=5555

# Everything the pipeline generates lives under workspace/. Only logs/ and .utv-runtime.conf stay top level.
WORKSPACE="$ROOT/workspace"
ORIGINAL_ROOT="$WORKSPACE/original"
WORK_ROOT="$WORKSPACE/work"
BUILD_DIR="$WORKSPACE/build"
OUT_DIR="$WORKSPACE/out"
KEYS_DIR="$WORKSPACE/keys"
LOG_DIR="$ROOT/logs"
PATCHES_DIR="$ROOT/patches"  # runtime.js (core) + JS patches
SMALI_DIR="$PATCHES_DIR/smali"     # bootloader: smali templates and helpers

KEYSTORE="$KEYS_DIR/atv.keystore"
KEY_ALIAS="atv"
KEY_PASSWORD_FILE="$KEYS_DIR/password.txt"

SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export JAVA_HOME="${JAVA_HOME:-$JBR}"
KEYTOOL="$JAVA_HOME/bin/keytool"
ADB="$(command -v adb || echo "$SDK/platform-tools/adb")"

# Saved between runs in .utv-runtime.conf. Flags override them.
DEVICE_IP=""
APP_LABEL=""
VERSION=""
ASSUME_YES=0
DEVTOOLS=0

# ---- output -------------------------------------------------------------------------------------

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1;32m[%s]\033[0m \033[1m%s\033[0m\n' "$1" "$2" >&2; }

# ---- prompts ------------------------------------------------------------------------------------

# ask "Question" "default" -> answer on stdout. With --yes, returns the default.
ask() {
    local question="$1" default="${2:-}" answer
    if [ "$ASSUME_YES" = 1 ]; then
        [ -n "$default" ] || die "--yes given but no value for: $question"
        echo "$default"
        return
    fi
    if [ -n "$default" ]; then
        read -r -p "$question [$default]: " answer < /dev/tty
    else
        read -r -p "$question: " answer < /dev/tty
    fi
    echo "${answer:-$default}"
}

# confirm "Question" Y|N -> exit status. With --yes, takes the default.
confirm() {
    local question="$1" default="${2:-N}" answer hint="[y/N]"
    [ "$default" = Y ] && hint="[Y/n]"
    if [ "$ASSUME_YES" = 1 ]; then
        [ "$default" = Y ]
        return
    fi
    read -r -p "$question $hint " answer < /dev/tty
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

# Like confirm, but always asks (ignores --yes) and defaults to No. For destructive actions.
confirm_destructive() {
    local answer
    [ -t 0 ] || [ -r /dev/tty ] || die "refusing to $1 without an interactive terminal"
    read -r -p "$1 Type 'yes' to continue: " answer < /dev/tty
    [ "$answer" = yes ]
}

# ---- config -------------------------------------------------------------------------------------

load_config() {
    # shellcheck disable=SC1090
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
    return 0
}

save_config() {
    {
        echo "# Written by ./utv-runtime. Defaults for the next run."
        printf 'DEVICE_IP=%q\n' "$DEVICE_IP"
        printf 'APP_LABEL=%q\n' "$APP_LABEL"
        printf 'VERSION=%q\n' "$VERSION"
    } > "$CONFIG_FILE"
}

# ---- device -------------------------------------------------------------------------------------

serial() {
    case "$DEVICE_IP" in
        *:*) echo "$DEVICE_IP" ;;
        *) echo "$DEVICE_IP:$ADB_PORT" ;;
    esac
}

device() { "$ADB" -s "$(serial)" "$@"; }

# First versionName in dumpsys is the active one (the /data update, not the factory copy).
installed_version() {
    device shell dumpsys package "$1" | sed -n 's/^ *versionName=//p' | head -1 | tr -d '\r'
}

# ---- versions and files -------------------------------------------------------------------------

# Without a version from the TV or config, fall back to the newest folder in workspace/original/.
resolve_version() {
    if [ -z "$VERSION" ]; then
        VERSION="$(ls -1 "$ORIGINAL_ROOT" 2>/dev/null | sort -V | tail -1)"
    fi
    [ -n "$VERSION" ] || die "no version known. Run './utv-runtime pull' first."
}

original_dir() { echo "$ORIGINAL_ROOT/$VERSION"; }
work_dir() { echo "$WORK_ROOT/${1%.apk}"; }

# APKS = base.apk then every split, taken from what was pulled for this version.
load_apks() {
    resolve_version
    local dir file
    dir="$(original_dir)"
    [ -f "$dir/base.apk" ] || die "no workspace/original/$VERSION/base.apk. Run './utv-runtime pull' first."
    APKS=(base.apk)
    for file in "$dir"/split_*.apk; do
        [ -e "$file" ] && APKS+=("$(basename "$file")")
    done
}

# Refuse to patch or build a decode of a different version than the one selected.
require_decoded() {
    load_apks
    local decoded
    decoded="$(cat "$WORK_ROOT/.version" 2>/dev/null || true)"
    [ -n "$decoded" ] || die "nothing decoded. Run './utv-runtime decode' first."
    [ "$decoded" = "$VERSION" ] || die "workspace/work/ holds $decoded but $VERSION is selected. Run './utv-runtime decode --force'."
}

resolve_build_tools() {
    BUILD_TOOLS="${BUILD_TOOLS:-$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1)}"
    [ -n "$BUILD_TOOLS" ] || die "no Android SDK build-tools in $SDK/build-tools"
    ZIPALIGN="$BUILD_TOOLS/zipalign"
    APKSIGNER="$BUILD_TOOLS/apksigner"
}
