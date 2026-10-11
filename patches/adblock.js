// adblock: strip video ad scheduling from InnerTube responses before the player sees them.
// Player responses carry the ad schedule in these keys; removing them means no ad breaks are set up.
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

utv.patch({
    id: "adblock",
    name: "Block ads",
    summary: "Remove video ads before they play",
    defaultEnabled: true,
    onResponse: function (response) {
        if (stripAds(response)) {
            stripped++;
            utv.report("adblock: stripped ads from response " + stripped);
        }
    }
});
