// shorts: hide YouTube Shorts, i.e. the Shorts entry in the main menu and Shorts shelves in feeds.
// Shorts only appear as their own shelves. Markers (language independent):
// - menu entry: guideEntryRenderer whose navigationEndpoint is a reelWatchEndpoint (applies on restart)
// - shelf: shelfRenderer.tvhtml5ShelfRendererType "TVHTML5_SHELF_RENDERER_TYPE_SHORTS" (Home rows,
//   continuations as you scroll, and other browse pages)
function isShorts(item) {
    if (!item || typeof item !== "object") return false;
    var entry = item.guideEntryRenderer;
    if (entry) return !!(entry.navigationEndpoint && entry.navigationEndpoint.reelWatchEndpoint);
    var shelf = item.shelfRenderer;
    return !!shelf && shelf.tvhtml5ShelfRendererType === "TVHTML5_SHELF_RENDERER_TYPE_SHORTS";
}

// Remove Shorts items from every array in the response. Returns how many were removed.
function removeShorts(node, depth) {
    if (!node || typeof node !== "object" || depth > 30) return 0;
    var removed = 0;
    if (Array.isArray(node)) {
        for (var i = node.length - 1; i >= 0; i--) {
            if (isShorts(node[i])) {
                node.splice(i, 1);
                removed++;
            } else {
                removed += removeShorts(node[i], depth + 1);
            }
        }
        return removed;
    }
    for (var key in node) {
        if (Object.prototype.hasOwnProperty.call(node, key)) removed += removeShorts(node[key], depth + 1);
    }
    return removed;
}

utv.patch({
    id: "shorts",
    name: "Hide Shorts",
    summary: "Remove Shorts shelves from feeds and Shorts from the main menu (menu applies after restarting the app)",
    defaultEnabled: true,
    onResponse: function (response) {
        var removed = removeShorts(response, 0);
        if (removed) utv.report("shorts: removed " + removed + " item(s)");
    }
});
