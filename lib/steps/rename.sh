# rename: change the package in every decoded manifest and set the launcher label. Safe to re-run,
# and the label can be changed on an already renamed decode.

step_rename() {
    require_decoded
    local name manifest
    for name in "${APKS[@]}"; do
        manifest="$(work_dir "$name")/AndroidManifest.xml"
        if rg -q "package=\"$NEW_PACKAGE\"" "$manifest"; then
            continue
        fi
        log "rename $PACKAGE -> $NEW_PACKAGE in workspace/work/${name%.apk}"
        # One pass over the package attr plus permission/process/taskAffinity names prefixed with it.
        # Components live under com.google.android.apps.*, so this never touches class names.
        sed -E -i '' "s/\"${PACKAGE//./\\.}([\".])/\"$NEW_PACKAGE\1/g" "$manifest"
    done

    # Label on <application>, whatever it currently is. XML-escaped; a leading @ or ? would be
    # read as a resource reference, so escape it.
    local label="${APP_LABEL:-$DEFAULT_LABEL}"
    LABEL="$label" perl -0pi -e '
        my $l = $ENV{LABEL};
        $l =~ s/&/&amp;/g; $l =~ s/</&lt;/g; $l =~ s/>/&gt;/g; $l =~ s/"/&quot;/g;
        $l =~ s/^([@?])/\\$1/;
        s/(<application\b[^>]*?\bandroid:label=")[^"]*"/$1$l"/ or die "no application label\n";
    ' "$(work_dir base.apk)/AndroidManifest.xml"
    log "label \"$label\""
}
