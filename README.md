# utv-runtime

A JavaScript patch runtime and development environment for the YouTube app on Android TV
(`com.google.android.youtube.tv`).

The app is a thin Android shell around Cobalt, Google's Chromium-based runtime for TVs, which runs
YouTube's TV web app from `youtube.com/tv`. utv-runtime patches the shell just enough to load your own
JavaScript into that web app, then lets you write features as small JS patches. Each patch gets its own
toggle inside YouTube's native Settings screen.

Everything is done with apktool and hand-written smali; no patching frameworks.

```
./utv-runtime            # guided: pull from the TV, patch, build, sign, install
```

## Included patches

| Patch | Setting (Settings > utv-runtime) | What it does |
| --- | --- | --- |
| `adblock` | Block ads | Strips video ad scheduling from player responses before the player sees it |
| `navigation` | Hide topic tabs | Removes Gaming, Podcasts, News, Music, Sport and Movies & TV from the main menu |
| `shorts` | Hide Shorts | Removes Shorts shelves from feeds and Shorts from the main menu |

All are on by default and can be switched off individually on the TV.

## How it works

```
 smali bootloader                    runtime core                      JS patches
 (patches/smali/)                    (patches/runtime.js)              (patches/*.js)
 ------------------                  --------------------              --------------
 rename + re-sign the app      ->    hooks every parsed InnerTube  ->  utv.patch({ id, name,
 survive Play Services refusals      response, log channel,            settings, onResponse })
 inject one JS bundle into           native Settings integration,
 every youtube.com/tv page           per-patch isolation
```

- **Bootloader (smali).** The patched app installs beside stock YouTube under its own package, so the
  stock app and its login are untouched. Smali patches make the re-signed app start, inject the bundle
  through Chromium's `evaluateJavaScript` on every page load, and expose a log channel. They locate
  everything by stable string anchors, never by obfuscated names.
- **Runtime core (JS).** Wraps `JSON.parse`, which YouTube uses for its InnerTube API responses, and runs
  each enabled patch over every response. Patch settings are registered as real YouTube client
  settings, so the app renders, toggles and stores them itself.
- **JS patches.** One file per feature. Adding one is a file in `patches/` and a rebuild; no smali.

Full API and rules: [docs/js-patches.md](docs/js-patches.md).

## Requirements

- macOS with Android Studio (SDK build-tools, platform-tools and the bundled JDK)
- `apktool`, `ripgrep`, `perl`; `jadx` is optional (for investigating new app versions)
- An Android TV with YouTube installed and network debugging enabled

`./utv-runtime doctor` checks all of these and offers to install apktool and jadx with Homebrew.

Tested on a TCL Smart TV Pro (Android 12, armeabi-v7a) with YouTube 7.21.302.

## Usage

```sh
./utv-runtime
```

The guided flow:

1. Checks tools.
2. Asks for the TV's IP and connects (accept the debugging prompt on the TV the first time).
3. Pulls the installed stock YouTube into `workspace/original/<version>/`, unless already there.
4. Asks for the launcher name of the patched app.
5. Decodes, renames, and applies all patches.
6. Builds, signs, installs over the previous patched build, compiles it, and offers to open it.

Answers are remembered in `.utv-runtime.conf`. Everything generated (originals, decodes, builds,
signed APKs, the signing key) lives under `workspace/`; logs go to `logs/`.

### Commands

```sh
./utv-runtime doctor                 # check tools
./utv-runtime pull                   # pull stock APKs into workspace/original/<version>/
./utv-runtime decode --force         # fresh decode into workspace/work/ + package rename
./utv-runtime patch                  # apply patches and bundle JS (safe to re-run; re-applies the name)
./utv-runtime build                  # rebuild, zipalign, sign into workspace/out/
./utv-runtime install                # install over the patched app, AOT compile
./utv-runtime logcat [--raw|--all]   # stream logs, saved to logs/
./utv-runtime eval '<js>'            # run JS in the live page (--devtools builds only)
```

Options: `--ip <address>`, `--name <label>`, `--version <ver>`, `--yes` (accept defaults; destructive
prompts still ask), `--devtools` (debug build, see below).

After editing a JS patch: `./utv-runtime patch && ./utv-runtime build && ./utv-runtime install`.

### Signing key

The first build creates `workspace/keys/atv.keystore`. **Back up `workspace/keys/`**: without it the
installed app can't be updated without uninstalling it (and signing in again). If that happens,
`install` offers to uninstall the patched app, never stock YouTube.

## Writing patches

A patch is one file in `patches/`:

```js
utv.patch({
    id: "shorts",
    name: "Hide Shorts",
    summary: "Remove Shorts shelves from feeds",
    defaultEnabled: true,
    onResponse: function (response, settings) {
        // mutate the parsed InnerTube response in place
    }
});
```

The core gives it a toggle in Settings > utv-runtime, only calls it while enabled, isolates its errors,
and hands back any extra settings it declares. See [docs/js-patches.md](docs/js-patches.md) for the API,
the settings model and the rules (ASCII only, logging, Trusted Types).

## Development environment

Chrome DevTools isn't compiled into this Cobalt build, so utv-runtime brings its own tooling.

```sh
./utv-runtime --devtools             # build and install a debug build
./utv-runtime eval 'utv.status()'    # run JS in the page; objects print as JSON, DOM nodes as HTML
./utv-runtime eval -f probe.js       # run a file
./utv-runtime eval                   # interactive utv> prompt
```

- **Live console.** `eval` sends code to the app over adb and prints the result. Use it to inspect the
  DOM, read renderer JSON and prototype patches without rebuilding.
- **Logging.** Injected code logs with `utv.report("message")` (logcat tag `utv-runtime`). Console
  output from injected code never reaches logcat.
- **Capture mode.** Records raw responses from page load, including ones parsed once at startup such as
  the main menu: see "Capture mode" in [docs/js-patches.md](docs/js-patches.md).
- **Findings.** [PATCHES.md](PATCHES.md) records how the app and its responses are structured (renderer
  shapes, the settings registry, menu and Shorts markers), with fingerprints for every patch.

Switch back with a plain `./utv-runtime` when you're done: in a debug build any app on the TV can run
JS inside the patched app.

## After a YouTube update

1. Let the TV update stock YouTube, then run `./utv-runtime`. It pulls the new version into its own
   `workspace/original/<version>/` folder and rebuilds.
2. If a smali patch stops with "anchor not found" or "shape changed", follow its fingerprint in
   `PATCHES.md` to find the new location in `jadx` output, then update `lib/steps/patch.sh`.
3. If a feature stops working but nothing fails, YouTube changed a response shape: inspect it with a
   `--devtools` build and update the JS patch. If the "utv-runtime" Settings category disappears, the
   settings registry moved (Finding 7 in `PATCHES.md`); patches keep running with their defaults.
4. Record the new version and results in `PATCHES.md`.

## Limitations

- The patched app is a separate app (default package `com.utv.runtime`, launcher name "UTV"): the remote's YouTube button and launcher links open stock YouTube,
  and casting from a phone most likely lands in stock YouTube too.
- Play Services features that check Google's signature (such as DroidGuard attestation) fail quietly in
  the patched app. Sign-in and playback work.
- Settings are on/off toggles only for now; list-style settings are planned.

## Project layout

```
utv-runtime              the CLI
lib/                     CLI steps (doctor, pull, decode, patch, build, install, logcat, eval)
patches/runtime.js       JS runtime core
patches/*.js             JS patches
patches/smali/           smali bootloader templates and helpers
docs/js-patches.md       JS patch API and development guide
PATCHES.md               findings, patch log and fingerprints
workspace/  logs/        generated (gitignored)
```

## License

[MIT](LICENSE). This covers the code in this repository only, not the YouTube app it patches.

## Disclaimer

Unofficial and not affiliated with or endorsed by Google or YouTube. A personal project for modifying
an app on your own device. It doesn't include or distribute any YouTube APKs: it works on the copy
already installed on your TV. Use at your own risk and in line with the terms that apply to you.
