# build: rebuild every decoded APK, zipalign, and sign all with the shared keystore into workspace/out/.

step_build() {
    require_decoded
    resolve_build_tools
    ensure_keystore

    rm -rf "$BUILD_DIR" "$OUT_DIR"
    mkdir -p "$BUILD_DIR" "$OUT_DIR"

    local name
    for name in "${APKS[@]}"; do
        log "build $name"
        apktool b -q "$(work_dir "$name")" -o "$BUILD_DIR/$name" 2>&1 | rg -v "JRSAppKit" >&2 || true
        [ -f "$BUILD_DIR/$name" ] || die "apktool build failed for $name (run 'apktool b workspace/work/${name%.apk}' to see why)"
    done

    for name in "${APKS[@]}"; do
        log "align + sign $name"
        # -p page-aligns the stored .so files (the app uses extractNativeLibs=false).
        "$ZIPALIGN" -f -p 4 "$BUILD_DIR/$name" "$BUILD_DIR/aligned-$name"
        "$APKSIGNER" sign --ks "$KEYSTORE" --ks-key-alias "$KEY_ALIAS" \
            --ks-pass "file:$KEY_PASSWORD_FILE" \
            --out "$OUT_DIR/$name" "$BUILD_DIR/aligned-$name"
        "$APKSIGNER" verify "$OUT_DIR/$name" >/dev/null || die "signature verification failed for $name"
    done
    rm -f "$OUT_DIR"/*.idsig
    log "signed APKs in workspace/out/"
}

# The one signing key, created on first use and never regenerated: a new key means the installed
# app can't be updated without uninstalling it (and losing its login).
ensure_keystore() {
    [ -f "$KEYSTORE" ] && return
    log "creating keystore (one time only, back up workspace/keys/)"
    mkdir -p "$KEYS_DIR"
    [ -f "$KEY_PASSWORD_FILE" ] || openssl rand -hex 16 > "$KEY_PASSWORD_FILE"
    chmod 600 "$KEY_PASSWORD_FILE"
    "$KEYTOOL" -genkeypair -keystore "$KEYSTORE" -alias "$KEY_ALIAS" \
        -keyalg RSA -keysize 4096 -validity 36500 -dname "CN=atv-utube" \
        -storepass:file "$KEY_PASSWORD_FILE" -keypass:file "$KEY_PASSWORD_FILE"
}
