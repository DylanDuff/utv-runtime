# install: install workspace/out/ as one split install over the patched app, then AOT compile it.
# Never touches stock YouTube. Only offers to uninstall the patched app on a signature mismatch.

step_install() {
    load_apks
    local files=() name result
    for name in "${APKS[@]}"; do
        [ -f "$OUT_DIR/$name" ] || die "missing workspace/out/$name. Run './atv build' first."
        files+=("$OUT_DIR/$name")
    done

    log "installing ${APKS[*]}"
    if ! result="$(device install-multiple -r "${files[@]}" 2>&1)"; then
        echo "$result" >&2
        case "$result" in
            *INSTALL_FAILED_UPDATE_INCOMPATIBLE*)
                warn "the installed $NEW_PACKAGE is signed with a different key (workspace/keys/ lost or regenerated?)"
                confirm_destructive "Uninstall $NEW_PACKAGE (NOT stock YouTube)? Its data and login are lost." \
                    || die "install aborted"
                device uninstall "$NEW_PACKAGE" >&2
                device install-multiple "${files[@]}" >&2
                ;;
            *) die "install failed" ;;
        esac
    fi

    # Sideloaded APKs start uncompiled (status=verify); stock is AOT compiled by the Play Store.
    log "compiling (takes a minute)"
    device shell cmd package compile -m speed -f "$NEW_PACKAGE" >/dev/null
    log "installed $NEW_PACKAGE $(installed_version "$NEW_PACKAGE")"
}

# Open the patched app on the TV.
launch_app() {
    device shell monkey -p "$NEW_PACKAGE" -c android.intent.category.LEANBACK_LAUNCHER 1 >/dev/null 2>&1
}
