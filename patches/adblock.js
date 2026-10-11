// Injected into https://www.youtube.com/tv by Lzz/AdBlockObserver; (see PATCHES.md "adblock-inject").
// Strips video ad scheduling from InnerTube responses as they are parsed.
// Keep this file ASCII only: patch.sh embeds it in smali as a string literal.
// report() logs to logcat (tag utv-runtime) by briefly setting document.title to "utv:<message>";
// AdBlockObserver.titleWasSet picks it up. Console output and uncaught errors never reach logcat.
(function () {
    if (location.hostname !== "www.youtube.com" || window.__atvAdblock) return;
    window.__atvAdblock = true;

    // Messages go out one per task so each title change reaches the browser, then the title is restored.
    var reportQueue = [];
    var savedTitle = null;
    function report(message) {
        reportQueue.push(message);
        if (reportQueue.length === 1 && savedTitle === null) setTimeout(flushReports, 0);
    }
    function flushReports() {
        if (savedTitle === null) savedTitle = document.title;
        if (reportQueue.length === 0) {
            document.title = savedTitle;
            savedTitle = null;
            return;
        }
        document.title = "utv:" + reportQueue.shift();
        setTimeout(flushReports, 0);
    }

    // Small global for other scripts (e.g. `utv-runtime eval` snippets) to log through.
    window.utv = { report: report };

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
            report("stripped ads from response " + stripped);
        }
        return result;
    };

    report("installed on " + location.href);
})();
