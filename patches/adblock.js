// Injected into https://www.youtube.com/tv by Lzz/AdBlockObserver; (see PATCHES.md "adblock-inject").
// Strips video ad scheduling from InnerTube responses as they are parsed.
// Keep this file ASCII only: patch.sh embeds it in smali as a string literal.
// Markers use console.error because Cobalt only forwards error-level console output to logcat.
(function () {
    if (location.hostname !== "www.youtube.com" || window.__atvAdblock) return;
    window.__atvAdblock = true;

    var AD_KEYS = ["adPlacements", "adSlots", "playerAds", "adBreakHeartbeatParams"];
    var stripped = 0;

    // Delete ad keys from a parsed response. Returns true if anything was removed.
    function stripAds(value) {
        var hit = false;
        for (var i = 0; i < AD_KEYS.length; i++) {
            if (Object.prototype.hasOwnProperty.call(value, AD_KEYS[i])) {
                delete value[AD_KEYS[i]];
                hit = true;
            }
        }
        // Player responses are sometimes nested, e.g. { playerResponse: {...} }.
        var nested = value.playerResponse;
        if (nested && typeof nested === "object") hit = stripAds(nested) || hit;
        return hit;
    }

    var parse = JSON.parse;
    JSON.parse = function () {
        var result = parse.apply(this, arguments);
        if (result && typeof result === "object" && stripAds(result)) {
            stripped++;
            console.error("atv-adblock: stripped " + stripped);
        }
        return result;
    };

    console.error("atv-adblock: installed on " + location.href);
})();
