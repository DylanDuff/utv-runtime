# patch: apply every smali patch to workspace/work/base. Each patch finds its file by a stable anchor (class
# and member names are obfuscated and change per version), writes a "# PATCH <id>" marker, and is
# skipped when re-run. PATCHES.md documents each one with its fingerprint.

step_patch() {
    require_decoded
    BASE_DIR="$(work_dir base.apk)"
    patch_gms_security_graceful
    patch_runtime_inject
    patch_ua_stock_package
}

# The single smali file whose content matches $2 (fixed string), or die naming patch $1.
anchor_file() {
    local id="$1" anchor="$2" files
    files="$(rg -l -F -- "$anchor" "$BASE_DIR"/smali*)" || die "[$id] anchor not found: $anchor"
    [ "$(echo "$files" | wc -l)" -eq 1 ] || die "[$id] anchor matches several files: $(echo $files)"
    echo "$files"
}

applied() { rg -q -F "# PATCH $1" "$2"; }

# Insert smali $4 after the .locals line of method $3 in the file containing anchor $2.
patch_prologue() {
    local id="$1" anchor="$2" method="$3" code="$4" file snippet
    file="$(anchor_file "$id" "$anchor")"
    if applied "$id" "$file"; then
        log "[$id] already applied"
        return
    fi
    rg -q -F ".method $method" "$file" || die "[$id] method not found: $method"

    snippet="$(mktemp)"
    printf '\n    # PATCH %s\n%s\n' "$id" "$code" > "$snippet"
    awk -v method=".method $method" -v snippet="$snippet" '
        index($0, method) { inside = 1 }
        { print }
        inside && /^[[:space:]]*\.locals/ {
            while ((getline line < snippet) > 0) print line
            inside = 0
        }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    rm -f "$snippet"
    log "[$id] patched ${file#$BASE_DIR/}"
}

# gms-security-graceful: BaseGmsClient.getRemoteService rethrows SecurityException, which Play
# Services raises for any package not signed by Google ("PackageVerificationRslt: not allowed").
# Route it to the handler used for every other failure (log + report connection failure code 8)
# so callers see a failed API connection instead of the app crashing.
patch_gms_security_graceful() {
    local id=gms-security-graceful anchor='"IGmsServiceBroker.getService failed"' file
    file="$(anchor_file "$id" "$anchor")"
    if applied "$id" "$file"; then
        log "[$id] already applied"
        return
    fi
    ANCHOR="$anchor" ID="$id" perl "$SMALI_DIR/$id.pl" < "$file" > "$file.tmp" \
        || { rm -f "$file.tmp"; die "[$id] patch failed"; }
    mv "$file.tmp" "$file"
    log "[$id] patched ${file#$BASE_DIR/}"
}

# runtime-inject: the bootloader. Adds Lzz/RuntimeObserver; (patches/smali/RuntimeObserver.smali) and registers it
# in dev.cobalt.shell.Shell next to StartupGuardNavigationObserver. It injects the runtime bundle
# (patches/runtime.js + patches/*.js) into each youtube.com/tv document. The class is regenerated on
# every run so JS edits apply without a fresh decode.
patch_runtime_inject() {
    local id=runtime-inject shell guard webcontents base_observer native_ptr script
    shell="$(anchor_file "$id" '.class public Ldev/cobalt/shell/Shell;')"
    guard="$(anchor_file "$id" '.class public final Ldev/cobalt/shell/StartupGuardNavigationObserver;')"
    webcontents="$(anchor_file "$id" '.class public Lcobalt/org/chromium/content/browser/webcontents/WebContentsImpl;')"
    anchor_file "$id" '.method public static cobalt_org_chromium_content_browser_webcontents_WebContentsImpl_evaluateJavaScript(JLjava/lang/Object;Ljava/lang/Object;)V' >/dev/null

    # Obfuscated names: the WebContentsObserver base is the guard's superclass, and the native
    # pointer is WebContentsImpl's only long field.
    base_observer="$(sed -n 's/^\.super \(L.*;\)$/\1/p' "$guard")"
    [ -n "$base_observer" ] || die "[$id] can't read observer superclass"
    native_ptr="$(sed -n 's/^\.field .* \([A-Za-z0-9_$]*\):J$/\1/p' "$webcontents")"
    [ "$(echo "$native_ptr" | wc -w)" -eq 1 ] || die "[$id] expected one long field in WebContentsImpl, got: $native_ptr"

    script="$(runtime_bundle "$id")"
    log "[$id] bundled runtime.js + $(runtime_patch_files | wc -l | tr -d ' ') JS patch(es): $(runtime_patch_files | xargs -n1 basename | tr '\n' ' ')"

    # --devtools builds add EvalReceiver (live JS console for `utv-runtime eval`). Both classes are
    # regenerated every run, so switching build type doesn't need a fresh decode.
    local classes="$BASE_DIR/smali_classes4/zz" devtools_init=""
    mkdir -p "$classes"
    rm -f "$classes/EvalReceiver.smali"
    if [ "$DEVTOOLS" = 1 ]; then
        devtools_init='    invoke-static {p0}, Lzz/EvalReceiver;->register(Lzz/RuntimeObserver;)V'
        cp "$SMALI_DIR/EvalReceiver.smali" "$classes/EvalReceiver.smali"
        warn "[$id] devtools build: any app on the TV can inject JS into the patched app"
    fi
    BASE_OBSERVER="$base_observer" NATIVE_PTR="$native_ptr" SCRIPT="$script" DEVTOOLS_INIT="$devtools_init" perl -pe '
        s/__BASE_OBSERVER__/$ENV{BASE_OBSERVER}/g;
        s/__NATIVE_PTR__/$ENV{NATIVE_PTR}/g;
        s/__SCRIPT__/$ENV{SCRIPT}/g;
        s/^__DEVTOOLS_INIT__$/$ENV{DEVTOOLS_INIT}/;
    ' "$SMALI_DIR/RuntimeObserver.smali" > "$classes/RuntimeObserver.smali"
    log "[$id] wrote RuntimeObserver (base $base_observer, pointer field $native_ptr)$([ "$DEVTOOLS" = 1 ] && echo " + EvalReceiver")"

    if applied "$id" "$shell"; then
        log "[$id] already registered"
        return
    fi
    # After "invoke-direct {pX, vY}, ...StartupGuardNavigationObserver;-><init>(...)V", reuse the
    # same registers: pX is free to clobber (it held the guard) and vY holds mWebContents.
    ID="$id" perl -pe '
        if (!$done && /^(\s*)invoke-direct \{(\w+), (\w+)\}, Ldev\/cobalt\/shell\/StartupGuardNavigationObserver;-><init>\(Lcobalt\/org\/chromium\/content_public\/browser\/WebContents;\)V/) {
            $_ .= "\n$1# PATCH $ENV{ID}\n$1new-instance $2, Lzz/RuntimeObserver;\n$1invoke-direct {$2, $3}, Lzz/RuntimeObserver;-><init>(Lcobalt/org/chromium/content_public/browser/WebContents;)V\n";
            $done = 1;
        }
        END { die "registration point not found\n" unless $done }
    ' "$shell" > "$shell.tmp" || { rm -f "$shell.tmp"; die "[$id] registration failed"; }
    mv "$shell.tmp" "$shell"
    log "[$id] registered in ${shell#$BASE_DIR/}"
}

# ua-stock-package: Cobalt appends getUserAgentAuxField() ("<package>/<versionName>") to the user
# agent. After the rename it reports the unknown patched package and YouTube serves it as a lower
# tier device (low resolution thumbnails). Report the stock package instead. The method name is
# unobfuscated because native code calls it through JNI.
patch_ua_stock_package() {
    local version_name
    version_name="$(sed -n 's/^  versionName: //p' "$BASE_DIR/apktool.yml")"
    [ -n "$version_name" ] || die "[ua-stock-package] versionName missing from apktool.yml"
    patch_prologue ua-stock-package \
        '.method protected getUserAgentAuxField()Ljava/lang/String;' \
        'protected getUserAgentAuxField()Ljava/lang/String;' \
"    const-string v0, \"$PACKAGE/$version_name\"
    return-object v0"
}

# JS patches in load order: everything in patches/ except the core, by filename.
runtime_patch_files() {
    find "$PATCHES_DIR" -maxdepth 1 -name '*.js' ! -name runtime.js | sort
}

# The injected script as one smali string literal: runtime.js first, then each JS patch wrapped in
# its own function scope (skipped where the core didn't load, e.g. non-YouTube pages). Comment lines
# and indentation are dropped, \ and " escaped, lines joined with \n.
runtime_bundle() {
    local id="$1" file
    for file in "$PATCHES_DIR/runtime.js" $(runtime_patch_files); do
        LC_ALL=C rg -q '[^\x00-\x7F]' "$file" && die "[$id] $(basename "$file") must be ASCII"
    done
    {
        cat "$PATCHES_DIR/runtime.js"
        for file in $(runtime_patch_files); do
            printf '(function () {\nif (!window.utv) return;\n'
            cat "$file"
            printf '\n})();\n'
        done
    } | sed -e '/^[[:space:]]*\/\//d' -e 's/^[[:space:]]*//' -e '/^$/d' \
      | perl -pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/'
}
