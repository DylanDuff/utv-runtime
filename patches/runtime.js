// utv-runtime core: injected into https://www.youtube.com/tv by Lzz/RuntimeObserver; (PATCHES.md "runtime-inject").
// Always loaded first. JS patches (patches/*.js) follow and register themselves with utv.patch().
// Keep every file ASCII only: patch.sh embeds the bundle in smali as a string literal.
//
// utv.patch({
//     id: "adblock",                   // [a-z0-9-]+, unique; becomes the client setting UTV_ADBLOCK
//     name: "Block ads",               // master toggle title in Settings > utv-runtime
//     summary: "...",                  // master toggle description
//     defaultEnabled: true,            // master toggle default (true if omitted)
//     settings: [{ key: "shorts", title: "...", summary: "...", default: false }],  // optional extras
//     onResponse: function (response, settings) { ... }  // each parsed InnerTube response, only while
// });                                                    // enabled; settings.get("shorts") reads extras
(function () {
    if (location.hostname !== "www.youtube.com" || window.utv) return;

    var parse = JSON.parse;

    // ---- log ----------------------------------------------------------------------------------
    // report() logs to logcat (tag utv-runtime) by briefly setting document.title to "utv:<message>";
    // RuntimeObserver.titleWasSet picks it up. Console output and uncaught errors never reach logcat.
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

    // ---- settings -----------------------------------------------------------------------------
    // Patch settings are registered as YouTube client settings, so the app renders, toggles and
    // stores them itself: localStorage "yt.leanback.default::<key>" = {"data": <bool>}.
    var STORAGE_PREFIX = "yt.leanback.default::";
    var settings = [];          // { key, title, summary, defaultValue } in display order
    var registry = null;        // YouTube's known global client settings ({ KEY: true })
    var defaults = null;        // YouTube's client setting defaults (Map)

    function readSetting(setting) {
        try {
            var stored = parse(localStorage.getItem(STORAGE_PREFIX + setting.key));
            if (stored && typeof stored.data === "boolean") return stored.data;
        } catch (e) {}
        return setting.defaultValue;
    }

    function registerSetting(setting) {
        registry[setting.key] = true;
        defaults.set(setting.key, setting.defaultValue);
    }

    // ClientSettingService only reads/writes keys in its registry and takes defaults from a Map.
    // Both are minified, so find them by content: the registry is the plain object holding
    // ENABLE_PREVIEWS_WITH_SOUND: true, the defaults the Map with that key.
    function findRegistry() {
        var namespace = window._yttv;
        if (!namespace) return false;
        var names = Object.keys(namespace);
        for (var i = 0; i < names.length && !(registry && defaults); i++) {
            var value;
            try { value = namespace[names[i]]; } catch (e) { continue; }
            if (!value || typeof value !== "object") continue;
            if (value instanceof Map) {
                if (!defaults && value.has("ENABLE_PREVIEWS_WITH_SOUND")) defaults = value;
            } else if (!registry && !Array.isArray(value) && value.ENABLE_PREVIEWS_WITH_SOUND === true) {
                registry = value;
            }
        }
        if (!registry || !defaults) {
            registry = defaults = null;
            return false;
        }
        settings.forEach(registerSetting);
        report("settings: registered " + settings.length + " client setting(s)");
        return true;
    }

    (function pollRegistry(attempt) {
        if (findRegistry()) return;
        if (attempt >= 600) {
            report("settings: client setting registry not found, Settings category disabled");
            return;
        }
        setTimeout(function () { pollRegistry(attempt + 1); }, 100);
    })(0);

    function runs(text) { return { runs: [{ text: text }] }; }
    function clientSettingEndpoint(key, value) {
        return { setClientSettingEndpoint: { settingDatas: [{ clientSettingEnum: { item: key }, boolValue: value }] } };
    }

    // The raw Settings response is items[] of settingCategoryCollectionRenderer; the app turns each
    // category into a heading plus tabs. Ours goes right after the first (untitled) category, and only
    // once the registry is patched, so a toggle is never shown that the app can't store.
    function injectSettingsCategory(response) {
        var items = response.items;
        if (!registry || !settings.length || !Array.isArray(items)) return;
        var isSettings = false;
        for (var i = 0; i < items.length; i++) {
            var category = items[i] && items[i].settingCategoryCollectionRenderer;
            if (!category) continue;
            if (category.categoryId === "SETTING_CAT_UTV_RUNTIME") return;
            isSettings = true;
        }
        if (!isSettings) return;
        items.splice(1, 0, { settingCategoryCollectionRenderer: {
            title: runs("utv-runtime"),
            categoryId: "SETTING_CAT_UTV_RUNTIME",
            focused: false,
            items: settings.map(function (setting) {
                return { settingBooleanRenderer: {
                    title: runs(setting.title),
                    summary: runs(setting.summary || ""),
                    enableServiceEndpoint: clientSettingEndpoint(setting.key, true),
                    disableServiceEndpoint: clientSettingEndpoint(setting.key, false),
                    itemId: setting.key
                } };
            })
        } });
    }

    // ---- patches ------------------------------------------------------------------------------
    var patches = [];

    function settingKey(patchId, key) {
        return ("UTV_" + patchId + (key ? "_" + key : "")).toUpperCase().replace(/[^A-Z0-9]/g, "_");
    }

    function definePatch(definition) {
        var id = definition && definition.id;
        if (!/^[a-z0-9-]+$/.test(id || "")) return report("patch rejected: invalid id " + id);
        for (var i = 0; i < patches.length; i++) {
            if (patches[i].id === id) return;   // already defined (e.g. injected twice)
        }

        var master = {
            key: settingKey(id),
            title: definition.name || id,
            summary: definition.summary,
            defaultValue: definition.defaultEnabled !== false
        };
        var extras = {};
        var own = [master];
        (definition.settings || []).forEach(function (extra) {
            var setting = {
                key: settingKey(id, extra.key),
                title: extra.title || extra.key,
                summary: extra.summary,
                defaultValue: !!extra.default
            };
            extras[extra.key] = setting;
            own.push(setting);
        });
        own.forEach(function (setting) {
            settings.push(setting);
            if (registry) registerSetting(setting);
        });

        patches.push({
            id: id,
            definition: definition,
            enabled: function () { return readSetting(master); },
            // Handed to the patch's hooks: its own extra settings by their short key.
            settings: {
                get: function (key) { return extras[key] ? readSetting(extras[key]) : undefined; }
            }
        });
    }

    // ---- capture (debugging) ------------------------------------------------------------------
    // With localStorage["utv-runtime::capture"] set (e.g. via `utv-runtime eval`), keep the raw text of
    // the first 15 responses after page load (startup: guide, home) and the latest 15, inspectable with
    // utv.captured(). Raw text, because the app rewrites parsed objects afterwards.
    var CAPTURE_FLAG = "utv-runtime::capture";
    var capturing = false;
    var captured = [];
    try { capturing = !!localStorage.getItem(CAPTURE_FLAG); } catch (e) {}
    if (capturing) report("capture mode on (clear with localStorage.removeItem(\"" + CAPTURE_FLAG + "\"))");

    // ---- response hook ------------------------------------------------------------------------
    JSON.parse = function (text) {
        var result = parse.apply(this, arguments);
        if (!result || typeof result !== "object") return result;
        if (capturing && typeof text === "string" && text.length > 500) {
            captured.push({ time: Date.now(), size: text.length, keys: Object.keys(result).slice(0, 8), text: text });
            if (captured.length > 30) captured.splice(15, 1);
        }
        try {
            injectSettingsCategory(result);
        } catch (e) {
            report("settings: inject failed: " + e);
        }
        for (var i = 0; i < patches.length; i++) {
            var patch = patches[i];
            if (typeof patch.definition.onResponse !== "function" || !patch.enabled()) continue;
            try {
                patch.definition.onResponse(result, patch.settings);
            } catch (e) {
                report(patch.id + ": onResponse failed: " + e);
            }
        }
        return result;
    };

    window.utv = {
        report: report,
        patch: definePatch,
        captured: function () { return captured; },
        // For debugging (`utv-runtime eval 'utv.status()'`).
        status: function () {
            return {
                registry: !!registry,
                patches: patches.map(function (p) { return p.id + (p.enabled() ? " (on)" : " (off)"); }),
                settings: settings.map(function (s) { return s.key + "=" + readSetting(s); })
            };
        }
    };
    report("core installed on " + location.href);
})();
