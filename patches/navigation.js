// navigation: remove topic tabs (Gaming, Podcasts, News, Music, Sport, Movies & TV) from the main guide.
// The guide response (fetched at startup) is items[].guideSectionRenderer.items[] of guideEntryRenderer;
// topic tabs browse to "FEtopics_<topic>" (Home is plain "FEtopics" and stays). Matching on browseId
// works in every UI language and also catches topics YouTube adds later. Applies on app restart.
function isTopicTab(entry) {
    var renderer = entry && entry.guideEntryRenderer;
    var browse = renderer && renderer.navigationEndpoint && renderer.navigationEndpoint.browseEndpoint;
    return !!browse && /^FEtopics_./.test(browse.browseId || "");
}

utv.patch({
    id: "navigation",
    name: "Hide topic tabs",
    summary: "Remove Gaming, Podcasts, News, Music, Sport and Movies & TV from the main menu (applies after restarting the app)",
    defaultEnabled: true,
    onResponse: function (response) {
        if (!Array.isArray(response.items)) return;
        var removed = 0;
        response.items.forEach(function (item) {
            var section = item && item.guideSectionRenderer;
            if (!section || !Array.isArray(section.items)) return;
            var kept = section.items.filter(function (entry) { return !isTopicTab(entry); });
            removed += section.items.length - kept.length;
            section.items = kept;
        });
        if (removed) utv.report("navigation: removed " + removed + " topic tab(s)");
    }
});
