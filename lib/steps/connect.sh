# connect: adb over the network to the TV, waiting for the on-screen debugging prompt if needed.

step_connect() {
    [ -n "$DEVICE_IP" ] || die "no TV IP. Pass --ip or run './atv' to be asked."
    log "connecting to $(serial)"
    "$ADB" connect "$(serial)" >/dev/null 2>&1 || true

    local state="" tries=0
    while [ "$tries" -lt 30 ]; do
        state="$("$ADB" -s "$(serial)" get-state 2>&1 || true)"
        case "$state" in
            device) break ;;
            *unauthorized*)
                [ "$tries" = 0 ] && warn "accept the USB debugging prompt on the TV (waiting up to 30s)"
                ;;
            *)
                "$ADB" connect "$(serial)" >/dev/null 2>&1 || true
                ;;
        esac
        tries=$((tries + 1))
        sleep 1
    done
    [ "$state" = device ] || die "can't reach $(serial) ($state). Check the IP and that network debugging is on."
    log "connected: $(device shell getprop ro.product.model | tr -d '\r'), Android $(device shell getprop ro.build.version.release | tr -d '\r')"
}
