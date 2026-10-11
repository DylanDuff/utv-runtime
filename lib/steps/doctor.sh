# doctor: check every tool the pipeline needs. Offers to brew-install apktool/jadx if missing.

step_doctor() {
    local missing=0 tool

    for tool in apktool jadx; do
        if ! command -v "$tool" >/dev/null; then
            warn "$tool not found"
            if command -v brew >/dev/null && confirm "Install $tool with Homebrew?" N; then
                brew install "$tool"
            elif [ "$tool" = apktool ]; then
                missing=1
            fi
        fi
    done

    resolve_build_tools
    check_tool "adb" "$ADB" || missing=1
    check_tool "apktool" "$(command -v apktool || true)" || missing=1
    check_tool "jadx (optional, for investigating new versions)" "$(command -v jadx || true)" || true
    check_tool "zipalign" "$ZIPALIGN" || missing=1
    check_tool "apksigner" "$APKSIGNER" || missing=1
    check_tool "keytool" "$KEYTOOL" || missing=1
    check_tool "ripgrep" "$(command -v rg || true)" || missing=1
    check_tool "perl" "$(command -v perl || true)" || missing=1

    [ "$missing" = 0 ] || die "missing required tools (see above)"
    log "apktool $(apktool --version 2>/dev/null | head -1), build-tools $(basename "$BUILD_TOOLS")"
}

check_tool() {
    local name="$1" path="$2"
    if [ -n "$path" ] && [ -x "$path" ]; then
        log "ok  $name"
        return 0
    fi
    warn "missing $name${path:+ (looked at $path)}"
    return 1
}
