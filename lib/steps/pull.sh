# pull: copy the installed stock APKs into workspace/original/<versionName>/. Never overwrites anything.

step_pull() {
    VERSION="$(installed_version "$PACKAGE")"
    [ -n "$VERSION" ] || die "$PACKAGE is not installed on the TV"
    log "installed $PACKAGE: $VERSION"

    local dir paths path
    dir="$(original_dir)"
    if [ -d "$dir" ]; then
        log "workspace/original/$VERSION already exists, not pulling"
        return
    fi

    paths="$(device shell pm path "$PACKAGE" | sed 's/^package://' | tr -d '\r')"
    [ -n "$paths" ] || die "pm path returned nothing for $PACKAGE"

    # Pull into a temp folder and move it into place only when complete.
    local staging="$ORIGINAL_ROOT/.pulling-$VERSION"
    rm -rf "$staging"
    mkdir -p "$staging"
    for path in $paths; do
        log "pull $(basename "$path")"
        device pull "$path" "$staging/$(basename "$path")" >/dev/null
    done
    mv "$staging" "$dir"
    chmod a-w "$dir"/*.apk
    ( cd "$dir" && shasum -a 256 *.apk ) >&2
}
