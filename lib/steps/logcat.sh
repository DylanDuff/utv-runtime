# logcat: stream device logs and save a copy to logs/.
#   (default)  crashes plus lines from the app, Cobalt, Chromium and auth
#   --raw      everything, unfiltered
#   --all      only the running patched app's pid

step_logcat() {
    device logcat -c
    mkdir -p "$LOG_DIR"
    local logfile pid
    logfile="$LOG_DIR/logcat-$(date +%Y%m%d-%H%M%S).txt"
    log "saving to ${logfile#$ROOT/} (Ctrl+C to stop)"

    case "${1:-}" in
        --raw)
            device logcat -v time -b main,system,crash | tee "$logfile"
            ;;
        --all)
            pid="$(device shell pidof "$NEW_PACKAGE" | tr -d '\r')"
            [ -n "$pid" ] || die "$NEW_PACKAGE is not running, launch it first"
            device logcat -v time --pid="$pid" | tee "$logfile"
            ;;
        *)
            device logcat -v time -b main,system,crash \
                | rg --line-buffered -i "AndroidRuntime|FATAL|$NEW_PACKAGE|atv-adblock|cobalt|chromium|GmsClient|ActivityManager: (Start|Process .* died)" \
                | tee "$logfile"
            ;;
    esac
}
