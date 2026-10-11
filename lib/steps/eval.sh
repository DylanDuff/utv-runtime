# eval: run JS in the patched app's page and print the result (needs a --devtools build).
#   eval '<js>'      run once
#   eval -f file.js  run a file
#   eval             interactive prompt
# The snippet is base64'd into an EVAL broadcast; the page answers over the title log channel with
# the result base64'd (titles collapse whitespace) and split into chunks the CLI reassembles.

EVAL_TIMEOUT=10
EVAL_CHUNK=900

step_eval() {
    if [ "${1:-}" = -f ]; then
        [ -f "${2:-}" ] || die "eval -f needs a file"
        eval_js "$(cat "$2")"
    elif [ $# -gt 0 ]; then
        eval_js "$*"
    else
        log "interactive eval on $NEW_PACKAGE (Ctrl+D to quit). 'utv.report(msg)' logs from code."
        local line
        while IFS= read -r -e -p "utv> " line; do
            [ -n "$line" ] || continue
            history -s "$line"
            eval_js "$line" || true
        done
        echo >&2
    fi
}

eval_js() {
    local code="$1" id wrapped tmp reader deadline
    id="e$(date +%s)$RANDOM"
    wrapped="$(eval_wrapper "$id" "$(printf '%s' "$code" | base64 | tr -d '\n')")"

    tmp="$(mktemp)"
    device logcat -v raw -T 1 -s utv-runtime:I > "$tmp" 2>/dev/null &
    reader=$!
    sleep 0.5
    device shell am broadcast -a dev.utv.runtime.EVAL -p "$NEW_PACKAGE" \
        --es js64 "$(printf '%s' "$wrapped" | base64 | tr -d '\n')" >/dev/null

    # Chunks arrive as "utv:eval:<id>:<i>/<n>:<base64 piece>".
    local result="" total="" received
    deadline=$((SECONDS + EVAL_TIMEOUT))
    while [ "$SECONDS" -lt "$deadline" ]; do
        total="$(sed -n "s/^utv:eval:$id:[0-9]*\/\([0-9]*\):.*/\1/p" "$tmp" | head -1)"
        received="$(rg -c "^utv:eval:$id:" "$tmp" || true)"
        if [ -n "$total" ] && [ "${received:-0}" -ge "$total" ]; then
            result="$(sed -n "s/^utv:eval:$id:[0-9]*\/[0-9]*://p" "$tmp" | tr -d '\n')"
            break
        fi
        sleep 0.2
    done
    kill "$reader" 2>/dev/null || true
    wait "$reader" 2>/dev/null || true
    rm -f "$tmp"

    if [ -z "$total" ]; then
        warn "no answer in ${EVAL_TIMEOUT}s. Is the app open, and was it built with --devtools?"
        return 1
    fi
    printf '%s' "$result" | base64 --decode
    echo
}

# JS that runs the snippet (indirect eval = global scope), awaits promises, formats the result
# (DOM nodes as outerHTML, objects as JSON) and reports it base64'd in chunks.
eval_wrapper() {
    local id="$1" code64="$2"
    cat <<EOF
(function () {
    var id = "$id";
    var report = (window.utv && window.utv.report) || function (m) { document.title = "utv:" + m; };
    function send(text) {
        var data = btoa(unescape(encodeURIComponent(String(text))));
        var count = Math.max(1, Math.ceil(data.length / $EVAL_CHUNK));
        for (var i = 0; i < count; i++) {
            report("eval:" + id + ":" + (i + 1) + "/" + count + ":" + data.substr(i * $EVAL_CHUNK, $EVAL_CHUNK));
        }
    }
    function format(value) {
        if (typeof value === "string") return value;
        if (value === undefined) return "undefined";
        if (typeof Node !== "undefined" && value instanceof Node) return value.outerHTML || String(value);
        if (typeof value === "function") return String(value);
        try { return JSON.stringify(value, null, 2); } catch (e) { return String(value); }
    }
    // youtube.com/tv enforces Trusted Types (require-trusted-types-for 'script'), so eval() only
    // accepts a TrustedScript. One pass-through policy is created per page and reused.
    function trusted(source) {
        if (!window.trustedTypes || !window.trustedTypes.createPolicy) return source;
        if (!window.__utvEvalPolicy) {
            window.__utvEvalPolicy = window.trustedTypes.createPolicy("utv-eval", {
                createScript: function (s) { return s; }
            });
        }
        return window.__utvEvalPolicy.createScript(source);
    }
    try {
        var result = (0, eval)(trusted(decodeURIComponent(escape(atob("$code64")))));
        if (result && typeof result.then === "function") {
            result.then(function (v) { send(format(v)); }, function (e) { send("error: " + e); });
        } else {
            send(format(result));
        }
    } catch (e) {
        send("error: " + e);
    }
})();
EOF
}
