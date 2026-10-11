# Patches and findings

Log of every target tried against the YouTube Android TV app, so the work can be
redone after an update by re-finding the same anchors. Class and method names are
obfuscated and change between versions; rely on the string anchors and shapes.

## Target build

| Field | Value |
| --- | --- |
| Package | `com.google.android.youtube.tv` |
| versionName | 7.21.302 |
| versionCode | 721302320 |
| minSdk / targetSdk | 29 / 36 |
| Splits | `base.apk`, `split_config.armeabi_v7a.apk` (native libs only) |
| Device | Android 12 (SDK 31), armeabi-v7a, 192.168.20.10 |
| Originals | `workspace/original/7.21.302/` |
| base.apk sha256 | `13cdb0b8709524574e7abc8a1d76e97ff99fec3dcc08492c4fc586e8a3b43166` |
| split sha256 | `4c2ee0ccac9d2493f98a8ac79c54472874909e5de80f3ab09522250e6c59ff7a` |

## Finding 1: the app is a system app, so it can't be replaced in place

- Factory copy at `/product/app/YouTubeLeanback` (5.12.300, Google signed). 7.21.302 is an
  `UPDATED_SYSTEM_APP` in `/data/app`.
- An unmodified apktool rebuild, re-signed with `keys/atv.keystore`, is rejected:
  `INSTALL_FAILED_UPDATE_INCOMPATIBLE: ... signatures do not match previously installed version`.
- Uninstalling won't help without root: `adb uninstall` only rolls back to the factory
  copy, and its Google signature still blocks the install. Uninstalling also wipes the login.
- Non-root option: rename the package so the patched app installs next to stock. Both
  `base.apk` and the split must be renamed, because every split's manifest `package`
  must match the base.

Manifest notes for a rename (7.21.302):
- No `<provider>` elements, so there are no authorities to rewrite.
- All components use fully qualified class names, so changing `package` doesn't break them.
- Strings to rewrite: `package`, permission `com.google.android.youtube.tv.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`,
  and optionally the process and taskAffinity names `com.google.android.youtube.tv.{main,player,recommendations}`.
- Package literals in code: only a Google package list (`duo`) and `"com.google.android.youtube.tv.prodlogger"` (`gcy`).
  Neither looks like a self check.
- `extractNativeLibs="false"`: the `.so` files must stay stored (uncompressed) and page aligned (`zipalign -p 4`).

## Finding 2: the UI and ad logic are not in Java/smali (Cobalt)

7.21.302 is a Cobalt app ("chrobalt", Chromium-based Cobalt). The Java layer is a thin shell:

- `split_config.armeabi_v7a.apk` holds `libchrobalt.so` (64 MB), the browser engine.
- `dev/cobalt/coat/CobaltActivity` loads a startup URL and requires it to start with
  `https://www.youtube.com/tv` (anchor string). `dev/cobalt/shell/StartupGuardNavigationObserver`
  enforces the same prefix.
- The UI, player and ad scheduling are JavaScript served by `youtube.com/tv` at runtime.
- jadx search across all dex: `adPlacements`, `playerAds`, `adSlots`, `instream` have **0 hits**.
  The only `adBreak` hits are the Cast SDK (`AdBreakInfo`, `AdBreakClipInfo`, `AdBreakStatus`).

Result: no Java method initiates the video ad load, so `return-void` smali patches can't remove ads.

Possible hook: the bundled Chromium content layer exposes JS execution through JNI:
- `WebContentsImpl.evaluateJavaScript` (`GEN_JNI.cobalt_org_chromium_content_browser_webcontents_WebContentsImpl_evaluateJavaScript`)
- `RenderFrameHostImpl.executeJavaScriptInIsolatedWorld`
- `JavascriptInjectorImpl` (used in `dev/cobalt/shell/Shell`)

A smali patch could inject a script on page load that strips ad fields from player
responses. Not yet attempted.

## Finding 3: renamed + re-signed build crashes on startup (GMS DroidGuard refusal)

Test: package renamed to `com.google.android.youtube.tv.adfree`, label "YouTube Test", no other
changes, installed beside stock. (Logs from this and the next two tests were lost: they were saved
in `build/` (now `workspace/build/`), which every build wipes. Logs now go to `logs/`.)

Result: launches, starts loading `https://www.youtube.com/tv`, then crashes about 6 s in, every launch:

```
FATAL EXCEPTION: DG
java.lang.SecurityException: PackageVerificationRslt: not allowed:
  pkg=com.google.android.youtube.tv.adfree, sha256=[29d26ca7...], atk=false
  at cyf.r -> cyc.a -> cye.b -> cxx.c -> cxy.handleMessage
```

Cause (confirmed with an unfiltered log):
- The web app opens Cobalt platform services on startup: `com.google.android.gms.droidguard`,
  `com.google.android.gms.cast.tv`, `com.google.youtube.tv.syncauthcredential`, `.syncdeviceid`,
  `.syncrollouttoken` (logged as `PlatformServiceImpl created for <name>`).
- The crash follows `com.google.android.gms.droidguard` (Java bridge `gcs`) every time. Play Services
  checks the caller cert against its Google allowlist and throws SecurityException.
- `cyf` is the obfuscated GMS `BaseGmsClient`; `r(...)` is `getRemoteService`, which deliberately
  rethrows SecurityException while handling every other failure gracefully.

Dead end, kept for reference: a first attempt (`po-token-disable`) short-circuited the PO Token
bridge (`gcw`, anchor `"Opening POTokensService"`). The app never opens that service before the
crash, so it had no effect and was removed.

---

# Patches

Smali patches, applied by `./utv-runtime patch` (`lib/steps/patch.sh`) in order. Each patch finds its file by string anchor and writes a
`# PATCH <id>` marker so re-running is a no-op.

## gms-security-graceful

| | |
| --- | --- |
| Purpose | Stop the app crashing when Play Services refuses a re-signed package |
| Class / method (7.21.302) | `cyf.r(Lczc;Ljava/util/Set;)V` in `smali_classes2/cyf.smali` (GMS `BaseGmsClient.getRemoteService`) |
| Anchor | `"IGmsServiceBroker.getService failed"` (only method containing it), also `"mServiceBroker is null, client disconnected"` |
| Change | SecurityException handler `move-exception v0; throw v0` becomes `move-exception v0; goto :<graceful>` |
| Logic | `patches/smali/gms-security-graceful.pl` |
| Result | App launches, plays video, **TV sign-in works**. Ads still play (expected). |

Fingerprint (labels are apktool-generated; find them by structure):
- Method has a `.catch Ljava/lang/SecurityException; {...} :catch_N` on two try ranges.
- `:catch_N` body is exactly `move-exception vX` then `throw vX`.
- The graceful path is the label right before `const-string vY, "GmsClient"` /
  `const-string vZ, "IGmsServiceBroker.getService failed"`, followed by `Log.w(...)` and a call to
  `A(ILandroid/os/IBinder;Landroid/os/Bundle;I)V` with code `0x8`, then `return-void`.
- The monitor is already exited before the catch handlers run, so the jump is safe.

Side effects: GMS-backed features (DroidGuard attestation, possibly Cast TV) silently fail.
Only 2 refusals logged per launch in the test.

## runtime-inject (bootloader)

Formerly `adblock-inject`. The smali side only loads JS; features live in JS patches
(see [docs/js-patches.md](docs/js-patches.md)).

| | |
| --- | --- |
| Purpose | Inject the runtime bundle (`patches/runtime.js` + `patches/*.js`) into every youtube.com/tv page |
| Files | `patches/smali/RuntimeObserver.smali` (template), `patches/runtime.js` (core), `patches/*.js` (JS patches) |
| New class | `Lzz/RuntimeObserver;` in `smali_classes4/` (own dex, avoids the 64K method limit) |
| Registered in | `dev.cobalt.shell.Shell.initFromNativeTabContents(WebContents)V`, right after `new StartupGuardNavigationObserver(mWebContents)` |
| Injection | `GEN_JNI.cobalt_org_chromium_content_browser_webcontents_WebContentsImpl_evaluateJavaScript(JLjava/lang/Object;Ljava/lang/Object;)V` with (native pointer, script, null) |
| Result | **Works.** Core loads, JS patches register, Settings category works, ads stripped. |

How it works:
- The observer overrides `primaryMainDocumentElementAvailable()V` and
  `didFinishNavigationInPrimaryMainFrame(NavigationHandle)V`, so it injects on every page load,
  including the return from the sign-in page. It never detaches.
- It also overrides `titleWasSet(String)V` for the log channel (Finding 5).
- Chromium did not block `evaluateJavaScript` on youtube.com/tv (no CHECK crash), so Cobalt allows
  JS injection from the embedder.
- Both generated classes are rewritten on every `patch` run, so JS edits need no fresh decode.

Fingerprint (resolved by `lib/steps/patch.sh` each run; nothing obfuscated is hardcoded):
- Observer base class (`Lbdn;` in 7.21.302) = `.super` of `Ldev/cobalt/shell/StartupGuardNavigationObserver;`.
- WebContents native pointer (`b:J` in 7.21.302) = the only `:J` field in
  `Lcobalt/org/chromium/content/browser/webcontents/WebContentsImpl;`.
- The `GEN_JNI` stub name is unobfuscated (jni_zero); its body is `N.VJOO(6, j, obj, obj2)`.
- The Java wrapper `WebContentsImpl.evaluateJavaScript` is stripped by R8; don't look for it.

## JS patch: adblock

| | |
| --- | --- |
| File | `patches/adblock.js` |
| Setting | "Block ads" (`UTV_ADBLOCK`), default on |
| Change | Deletes `adPlacements`, `adSlots`, `playerAds`, `adBreakHeartbeatParams` from every parsed response (and a nested `playerResponse`) |
| Result | **Works.** No ads seen across several videos. First direct confirmation: `adblock: stripped ads from response 1` on the home screen load. |

Verified by A/B (the `gms-security-graceful` build played ads) and by its own log line.

## JS patch: navigation

| | |
| --- | --- |
| File | `patches/navigation.js` |
| Setting | "Hide topic tabs" (`UTV_NAVIGATION`, default on) |
| Change | Removes `guideEntryRenderer`s whose `navigationEndpoint.browseEndpoint.browseId` is `FEtopics_<topic>` from every `guideSectionRenderer.items` (Gaming, Podcasts, News, Music, Sport, Movies & TV, and any topic added later). Home (`FEtopics`) stays. |
| Applies | When the guide loads, i.e. on app restart |
| Result | **Works.** Menu is Search, Home, Shorts, Subscriptions, Library, Settings. |

Planned: let the user pick which topics to hide with a multi-select setting, like YouTube's
preferred-languages setting. Needs multi-select support in the core first (see `docs/js-patches.md`).

## JS patch: shorts

| | |
| --- | --- |
| File | `patches/shorts.js` |
| Setting | "Hide Shorts" (`UTV_SHORTS`, default on) |
| Change | Removes, from every array in every response: the `guideEntryRenderer` whose `navigationEndpoint` is a `reelWatchEndpoint` (menu entry), and every `shelfRenderer` with `tvhtml5ShelfRendererType: "TVHTML5_SHELF_RENDERER_TYPE_SHORTS"` |
| Applies | Feeds: next loaded rows. Menu: on app restart |
| Result | **Works.** Menu is Search, Home, Subscriptions, Library, Settings; no Shorts shelves on Home while scrolling, loading more rows unaffected. |

## ua-stock-package

| | |
| --- | --- |
| Purpose | Report the stock package in the user agent instead of `.adfree` |
| Method | `dev.cobalt.coat.BaseStarboardBridge.getUserAgentAuxField()Ljava/lang/String;` (unobfuscated, called from native) |
| Change | Returns `"com.google.android.youtube.tv/<versionName>"` immediately; version read from `apktool.yml` at patch time |
| Why | Stock builds `<getApplicationInfo().packageName>/<versionName>`, which after the rename reported an unknown client. Suspected cause of lower resolution thumbnails. |
| Result | **Works.** Thumbnails back to full resolution after this patch (together with AOT compile). |

## Build notes

- `./utv-runtime install` runs `cmd package compile -m speed -f` after installing. A sideloaded APK starts
  as `status=verify` (interpreted/JIT); stock is `speed-profile` from the Play Store. Fixed the
  noticeably sluggish UI.

## Finding 4: no Chrome DevTools in this Cobalt build

- `libchrobalt.so` contains the `remote-debugging-port` switch name (Chromium defines all switch
  names centrally) but none of the DevTools HTTP server's strings (`webSocketDebuggerUrl`,
  `devtoolsFrontendUrl`, `/devtools/browser/`, "DevTools listening").
- Tested with a temporary patch (since removed) that added `--remote-debugging-port=9222` and
  `--remote-allow-origins=*` after `"--hide-scrollbars"` in `CobaltActivity`'s switch list
  (unknown switches pass straight through to Chromium).
  The engine logs `'remote-debugging-port': '9222'` but nothing listens on TCP 9222 and there is
  no devtools abstract socket. The server isn't compiled in.

## Finding 5: getting output out of injected JS

- `console.*` from injected code never reaches logcat (the `LogJsConsoleMessages` feature only shows
  Blink's own messages such as "Refused to set unsafe header").
- Uncaught errors thrown from a `setTimeout` in injected code don't appear either; YouTube's global
  error handler swallows them.
- **Works:** `report(msg)` in `runtime.js` sets `document.title = "utv:" + msg` (one message per
  task, title restored afterwards). `RuntimeObserver.titleWasSet(String)` logs titles starting with
  `utv:` under the logcat tag `utv-runtime`.
- First direct confirmation that the script runs and strips:
  `utv:installed on https://www.youtube.com/tv` about 120 ms after injection, then
  `utv:stripped ads from response 1` during the home screen load.

## Finding 6: page structure and security policy (7.21.302)

- UI is YouTube's Living Room web components: `ytlr-app`, `ytlr-tv-browse-renderer`,
  `ytlr-setting-action-renderer`, `yt-virtual-list`, Redux-connected elements
  (`ytlr-redux-connect-*`). Pages are renderers built from InnerTube JSON. Globals: `yt`, `ytcfg`, `_yttv`.
- The page enforces **Trusted Types** (`require-trusted-types-for 'script'`): `eval(string)` throws
  "Refused to evaluate a string as JavaScript". A pass-through policy works
  (`trustedTypes.createPolicy("utv-eval", { createScript: s => s })`), so policy names aren't restricted.
  `evaluateJavaScript` from the embedder isn't subject to it.
- User agent (after `ua-stock-package`): `... Cobalt/27.lts.3.1040801-gold ... (TCL, Smart TV Pro)
  com.google.android.youtube.tv/7.21.302`.

## devtools build: live JS console

Opt-in with `--devtools`. Never for everyday use: the receiver is exported, so any app on the TV
could inject JS into the patched app.

| | |
| --- | --- |
| Smali | `patches/smali/EvalReceiver.smali` (`Lzz/EvalReceiver;`), registered from the `RuntimeObserver` constructor via `__DEVTOOLS_INIT__` |
| Trigger | Broadcast `dev.utv.runtime.EVAL` to the patched package, extra `js64` = base64 script |
| Context | `ActivityThread.currentApplication()` by reflection (no app class or obfuscated name needed) |
| Result | Page reports `utv:eval:<id>:<i>/<n>:<base64 chunk>` over the title channel; CLI reassembles |
| CLI | `./utv-runtime eval '<js>'`, `eval -f file.js`, or `eval` for an interactive prompt |

Both generated classes are rewritten on every `patch` run, so switching between normal and devtools
builds doesn't need a fresh decode. Results are base64'd because titles collapse whitespace.

## Finding 7: native settings integration (7.21.302)

- The raw Settings response (top-level `items`, `title`, `titleRenderer`) is `items[]` of
  `settingCategoryCollectionRenderer { title?, categoryId, focused, items[] }`. The app rewrites it
  after parsing into `contents.tvBrowseRenderer.content.tvSecondaryNavRenderer` (categories become an
  unselectable heading tab plus one tab per setting), so hooks must match the raw `items` shape.
- Setting renderers seen: `settingActionRenderer`, `settingsPaneRenderer`, `settingBooleanRenderer`,
  `settingSingleOptionMenuRenderer`, `settingReadOnlyItemRenderer`, link-phone renderers.
- Booleans use `setSettingEndpoint` (account setting, numeric `settingItemId`, sent to the server) or
  `setClientSettingEndpoint` (`settingDatas[{clientSettingEnum:{item}, boolValue}]`, client only).
- Client settings are stored by `ClientSettingService` (anchor: that string in its error messages) in
  `localStorage["yt.leanback.default::<ITEM>"] = {"data": ...}` (per-identity ones as
  `{"data": {"<id>": v}}`). It only handles keys in a registry of known global settings (`_yttv.lOa`
  in 7.21.302, `{ KEY: true }`) and reads defaults from a Map (`_yttv.FD`). An unknown key renders
  but can't be toggled.
- Adding our key to both makes a custom `settingBooleanRenderer` fully native. Found by content: the
  plain object with `ENABLE_PREVIEWS_WITH_SOUND: true` and the Map that has that key. Verified live:
  toggling wrote `yt.leanback.default::UTV_ADBLOCK = {"data":false}`.
- Dead ends: matching `contents.tvBrowseRenderer` at parse time (that's the post-rewrite shape), and
  adding tabs directly.

## Finding 8: main navigation (guide) response (7.21.302)

- Fetched once at startup (so only visible with capture mode, see `docs/js-patches.md`). Top-level
  keys `responseContext, items, footer, topbar, startupBehaviours`.
- `items[0].guideSectionRenderer.items[]` is `guideEntryRenderer { formattedTitle, icon.iconType,
  navigationEndpoint }`: Search (`searchEndpoint`), Home (`browseId FEtopics`), Shorts
  (`reelWatchEndpoint`), Subscriptions (`FEsubscriptions`), Library (`FElibrary`), then topic tabs
  `FEtopics_gaming`, `_podcasts`, `_news`, `_music`, `_sports`, `_movies`. Settings comes from `footer`.
- The menu DOM is `ytlr-guide-response` > `ytlr-guide-entry-renderer`.

## Finding 9: Shorts in feeds (7.21.302)

- Shorts only appear as their own shelves, never mixed into normal rows.
- Home's first response has no Shorts; the Shorts shelf arrives in a scroll continuation
  (`continuationContents.sectionListContinuation.contents[]`). Other browse pages carry it under
  `contents.tvBrowseRenderer.content.tvSurfaceContentRenderer.content.sectionListRenderer.contents[]`.
- Shelf markers: `shelfRenderer.tvhtml5ShelfRendererType: "TVHTML5_SHELF_RENDERER_TYPE_SHORTS"`,
  header `shelfHeaderRenderer.avatarLockup.avatarLockupRenderer` with icon `YOUTUBE_SHORTS_FILL_24`.
- Tile markers (inside the shelf): `tileRenderer.style: "TILE_STYLE_YTLR_SHORTS"`,
  `contentType: "TILE_CONTENT_TYPE_SHORTS"` (not always present), `onSelectCommand.reelWatchEndpoint`.
- Menu entry: `guideEntryRenderer` with `navigationEndpoint.reelWatchEndpoint` (icon `YOUTUBE_SHORTS_FILL_24`).
