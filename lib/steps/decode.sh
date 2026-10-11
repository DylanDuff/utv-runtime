# decode: apktool-decode every APK of the selected version into workspace/work/<name>, then rename.
# workspace/work/ is disposable (all patches are scripted) but may hold hand edits, so replacing it needs --force.

step_decode() {
    load_apks
    if [ -d "$WORK_ROOT" ] && [ "${1:-}" != "--force" ]; then
        die "workspace/work/ already exists. Re-run with --force to replace it."
    fi

    rm -rf "$WORK_ROOT"
    mkdir -p "$WORK_ROOT"
    local name yml
    for name in "${APKS[@]}"; do
        log "decode workspace/original/$VERSION/$name"
        apktool d -q -f "$(original_dir)/$name" -o "$(work_dir "$name")" 2>&1 | rg -v "JRSAppKit" >&2 || true
        [ -f "$(work_dir "$name")/AndroidManifest.xml" ] || die "apktool failed on $name"

        # Splits without resources.arsc decode without usesFramework, so aapt2 can't resolve
        # android: attributes on rebuild. Point them at the framework too.
        yml="$(work_dir "$name")/apktool.yml"
        if ! rg -q '^usesFramework:' "$yml"; then
            sed -i '' '/^apkFileName:/a\
usesFramework:\
\  ids:\
\  - 1
' "$yml"
        fi
    done
    echo "$VERSION" > "$WORK_ROOT/.version"

    step_rename
}
