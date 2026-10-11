# JS patches

Features are JS patches in `patches/*.js`. The smali side is only a bootloader: `RuntimeObserver`
injects one bundle into every youtube.com/tv page, built from `patches/runtime.js` (the core) followed
by every other `patches/*.js` in filename order. Each patch file is wrapped in its own function scope,
so top-level `var`s and functions stay private to the file.

Add or edit a patch, then rebuild:

```sh
./utv-runtime patch && ./utv-runtime build && ./utv-runtime install
```

## API

```js
utv.patch({
    id: "adblock",                    // [a-z0-9-]+, unique
    name: "Block ads",                // master toggle title in Settings > utv-runtime
    summary: "Remove video ads...",   // master toggle description
    defaultEnabled: true,             // master toggle default (true if omitted)
    settings: [                       // optional extra booleans, shown under the master toggle
        { key: "shorts", title: "Hide Shorts", summary: "...", default: false }
    ],
    onResponse: function (response, settings) {
        // Called with every parsed InnerTube response (the object JSON.parse returned), only while
        // the master toggle is on. Mutate it in place. settings.get("shorts") reads an extra.
    }
});

utv.report("message");   // log to logcat under the tag utv-runtime
utv.status();            // { registry, patches, settings } for debugging via `utv-runtime eval`
```

## Settings

- Every patch gets a master on/off toggle. Its hooks only run while it is on, and the value is read
  for every response, so changes apply on the next response without a restart.
- Setting keys are derived from the ids: master `UTV_<ID>`, extras `UTV_<ID>_<KEY>` (upper case,
  non-alphanumerics become `_`). Renaming an id or key resets that setting to its default.
- The core registers the keys as YouTube client settings (in the app's known-settings registry and
  defaults Map, found by content), so the app renders the toggles, flips them and stores them itself in
  `localStorage["yt.leanback.default::<KEY>"] = {"data": <bool>}`.
- The "utv-runtime" category is only added to Settings after registration succeeds. If a future app
  version moves the registry, the core reports `settings: client setting registry not found` and patches
  keep running with their defaults.
- Only booleans for now (`settingBooleanRenderer`). Option lists would use `settingSingleOptionMenuRenderer`.

## Rules

- ASCII only (the bundle is embedded in smali as a string literal; the build refuses otherwise).
- Comment lines are stripped from the bundle, but only whole-line `//` comments. Don't put `//`
  comments after code on the same line.
- Don't log with `console.*` or rely on thrown errors: neither reaches logcat. Use `utv.report()`.
- `eval`/`new Function` on strings throw (the page enforces Trusted Types). Code in the bundle itself is fine.
- A patch's hook errors are caught and reported as `<id>: onResponse failed: ...`; they don't affect
  other patches.

## Developing against the live page

Use a `--devtools` build and `./utv-runtime eval` (see the README). Useful starting points:

```sh
./utv-runtime eval 'utv.status()'
./utv-runtime eval -f probe.js      # e.g. a JSON.parse wrapper that records responses to window
```

Findings about the page (renderer shapes, Trusted Types, the settings registry) are in `PATCHES.md`.
